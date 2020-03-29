"""
convect.ingest.client - Reconnecting TCP ingest client for the Convect engine.

Provides a high-level client that:
  - Connects to the X10 engine over TCP
  - Sends individual or batched sensor readings using the wire protocol
  - Automatically reconnects with exponential back-off on connection failure
  - Tracks ingestion statistics (sent, failed, bytes, latency)
  - Supports the context manager protocol for clean resource management
  - Drains any buffered readings on close

Thread safety: NOT thread-safe.  Use one client per thread or protect
external access with a lock.
"""

from __future__ import annotations

import logging
import socket
import time
from dataclasses import dataclass, field
from typing import List, Optional, Sequence

from ingest.protocol import ConvectProtocol, MessageType, Reading

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Ingestion statistics
# ---------------------------------------------------------------------------

@dataclass
class IngestStats:
    """Counters and metrics for a single client session.

    All latency values are in seconds.
    """

    readings_sent: int = 0
    readings_failed: int = 0
    batches_sent: int = 0
    bytes_sent: int = 0
    heartbeats_sent: int = 0
    total_latency: float = 0.0
    reconnect_count: int = 0
    _send_count: int = field(default=0, repr=False)

    @property
    def avg_latency(self) -> float:
        """Average send latency per network write, in seconds."""
        if self._send_count == 0:
            return 0.0
        return self.total_latency / self._send_count


# ---------------------------------------------------------------------------
# Back-off configuration
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class BackoffConfig:
    """Parameters for exponential back-off on reconnection attempts.

    Attributes:
        initial_delay: Seconds to wait before the first retry.
        max_delay:     Ceiling on the back-off delay.
        multiplier:    Factor by which the delay grows after each failure.
        max_retries:   Give up entirely after this many consecutive failures.
                       0 means retry forever.
    """

    initial_delay: float = 0.5
    max_delay: float = 30.0
    multiplier: float = 2.0
    max_retries: int = 10


# ---------------------------------------------------------------------------
# Client
# ---------------------------------------------------------------------------

class ConvectIngestClient:
    """TCP client that pushes sensor readings to the Convect X10 engine.

    Usage::

        with ConvectIngestClient("localhost", 9100) as client:
            client.send_reading(some_reading)
            client.send_batch(list_of_readings)

    The client maintains an internal buffer.  When *batch_size* readings
    accumulate, or when *flush_interval* seconds elapse since the last
    flush, the buffer is drained as a single batch frame.
    """

    def __init__(
        self,
        host: str,
        port: int,
        *,
        batch_size: int = 100,
        flush_interval: float = 1.0,
        backoff: Optional[BackoffConfig] = None,
        connect_timeout: float = 5.0,
        send_timeout: float = 10.0,
    ) -> None:
        """Initialize the client.

        Args:
            host:           Engine hostname or IP.
            port:           Engine ingest port.
            batch_size:     Number of readings to buffer before auto-flushing.
            flush_interval: Max seconds between automatic flushes.
            backoff:        Reconnection back-off parameters.
            connect_timeout: Socket connect timeout in seconds.
            send_timeout:    Socket send timeout in seconds.
        """
        self._host = host
        self._port = port
        self._batch_size = max(1, batch_size)
        self._flush_interval = flush_interval
        self._backoff = backoff or BackoffConfig()
        self._connect_timeout = connect_timeout
        self._send_timeout = send_timeout

        self._socket: Optional[socket.socket] = None
        self._buffer: List[Reading] = []
        self._last_flush_time: float = time.monotonic()
        self._connected: bool = False
        self.stats = IngestStats()

    # ---- context manager --------------------------------------------------

    def __enter__(self) -> ConvectIngestClient:
        self.connect()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:  # type: ignore[override]
        self.close()
        return None

    # ---- connection management --------------------------------------------

    def connect(self) -> None:
        """Establish (or re-establish) the TCP connection to the engine.

        Raises ConnectionError after exhausting all retry attempts.
        """
        if self._connected:
            return

        delay = self._backoff.initial_delay
        attempts = 0

        while True:
            attempts += 1
            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(self._connect_timeout)
                sock.connect((self._host, self._port))
                # Switch to a separate send timeout after the handshake.
                sock.settimeout(self._send_timeout)
                self._socket = sock
                self._connected = True
                logger.info(
                    "Connected to %s:%d (attempt %d)", self._host, self._port, attempts
                )
                return
            except OSError as exc:
                logger.warning(
                    "Connection attempt %d to %s:%d failed: %s",
                    attempts, self._host, self._port, exc,
                )
                if 0 < self._backoff.max_retries <= attempts:
                    raise ConnectionError(
                        f"Failed to connect to {self._host}:{self._port} "
                        f"after {attempts} attempts"
                    ) from exc

                time.sleep(delay)
                delay = min(delay * self._backoff.multiplier, self._backoff.max_delay)
                self.stats.reconnect_count += 1

    def _reconnect(self) -> None:
        """Close the current socket (if any) and try to reconnect."""
        self._disconnect()
        self.connect()

    def _disconnect(self) -> None:
        """Shut down the socket without raising."""
        self._connected = False
        if self._socket is not None:
            try:
                self._socket.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            try:
                self._socket.close()
            except OSError:
                pass
            self._socket = None

    # ---- low-level send ---------------------------------------------------

    def _send_raw(self, data: bytes) -> bool:
        """Send raw bytes over the socket, reconnecting on failure.

        Returns True on success, False if the send ultimately failed.
        """
        for attempt in range(2):  # at most one reconnect attempt
            if not self._connected:
                try:
                    self._reconnect()
                except ConnectionError:
                    return False

            try:
                start = time.monotonic()
                assert self._socket is not None
                self._socket.sendall(data)
                elapsed = time.monotonic() - start
                self.stats.bytes_sent += len(data)
                self.stats.total_latency += elapsed
                self.stats._send_count += 1
                return True
            except OSError as exc:
                logger.warning("Send failed (attempt %d): %s", attempt + 1, exc)
                self._disconnect()

        return False

    # ---- public send API --------------------------------------------------

    def send_reading(self, reading: Reading) -> bool:
        """Buffer a single reading, auto-flushing when the batch is full.

        Returns True if the reading was accepted into the buffer (it may
        not have been sent yet).  Returns False only if the buffer flush
        triggered by this call fails.
        """
        self._buffer.append(reading)
        if len(self._buffer) >= self._batch_size:
            return self.flush()
        # Also flush if enough time has passed.
        if time.monotonic() - self._last_flush_time >= self._flush_interval:
            return self.flush()
        return True

    def send_reading_immediate(self, reading: Reading) -> bool:
        """Send a single reading immediately (no buffering).

        Useful for low-volume or latency-sensitive paths.
        """
        frame = ConvectProtocol.encode_reading(reading)
        ok = self._send_raw(frame)
        if ok:
            self.stats.readings_sent += 1
        else:
            self.stats.readings_failed += 1
        return ok

    def send_batch(self, readings: Sequence[Reading]) -> bool:
        """Send a pre-assembled batch immediately, bypassing the buffer."""
        if not readings:
            return True
        frame = ConvectProtocol.encode_batch(list(readings))
        ok = self._send_raw(frame)
        if ok:
            self.stats.readings_sent += len(readings)
            self.stats.batches_sent += 1
        else:
            self.stats.readings_failed += len(readings)
        return ok

    def send_heartbeat(self, timestamp_ms: Optional[int] = None) -> bool:
        """Send a heartbeat frame to keep the connection alive."""
        if timestamp_ms is None:
            timestamp_ms = int(time.time() * 1000)
        frame = ConvectProtocol.encode_heartbeat(timestamp_ms)
        ok = self._send_raw(frame)
        if ok:
            self.stats.heartbeats_sent += 1
        return ok

    def send_control(self, command: str, args: str = "{}") -> bool:
        """Send a control command to the engine."""
        frame = ConvectProtocol.encode_control(command, args)
        return self._send_raw(frame)

    # ---- flush / drain ----------------------------------------------------

    def flush(self) -> bool:
        """Flush the internal buffer as a single batch frame.

        Returns True if the buffer was empty or the flush succeeded.
        """
        if not self._buffer:
            self._last_flush_time = time.monotonic()
            return True

        batch = self._buffer[:]
        self._buffer.clear()
        self._last_flush_time = time.monotonic()

        ok = self.send_batch(batch)
        if not ok:
            # Put the readings back so the caller can retry or inspect.
            self._buffer.extend(batch)
        return ok

    def close(self) -> None:
        """Drain buffered readings and close the connection gracefully."""
        # Best-effort drain: try to send whatever is buffered.
        if self._buffer and self._connected:
            self.flush()
        self._disconnect()
        logger.info(
            "Client closed. Stats: sent=%d failed=%d bytes=%d avg_latency=%.4fs",
            self.stats.readings_sent,
            self.stats.readings_failed,
            self.stats.bytes_sent,
            self.stats.avg_latency,
        )
