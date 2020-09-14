"""
convect.ingest.protocol - Binary wire protocol for the Convect X10 engine.

Defines the framing format used to send sensor data from Python ingest clients
to the X10 engine core over a TCP socket.  The protocol is intentionally simple
and self-describing so that a crash in the middle of a send does not corrupt
the stream -- every frame is independently verifiable via CRC32.

Wire format (big-endian):
    +--------+--------+--------+--------+----------+---------+
    | Magic  | Ver    | Type   | Length | Payload  | CRC32   |
    | 2B     | 1B     | 1B     | 4B     | variable | 4B      |
    +--------+--------+--------+--------+----------+---------+

    Magic   : 0xC0EC  -- chosen to be visually distinctive in hex dumps
    Version : protocol version byte (currently 1)
    Type    : MessageType enum value
    Length  : uint32 length of the payload section only
    Payload : type-specific binary payload (see below)
    CRC32   : IEEE CRC32 over bytes [Magic..Payload] inclusive

Payload layouts by message type:

SENSOR_READING (type 0x01):
    sensor_id   : uint16 length-prefixed UTF-8 string
    latitude    : float64 (IEEE 754)
    longitude   : float64
    timestamp   : int64 (milliseconds since Unix epoch)
    metric      : uint16 length-prefixed UTF-8 string
    value       : float64
    quality     : uint8

BATCH_READINGS (type 0x02):
    count       : uint32 number of readings
    readings[]  : repeated SENSOR_READING payloads (without per-reading framing)

HEARTBEAT (type 0x03):
    timestamp   : int64

CONTROL (type 0x04):
    command     : uint16 length-prefixed UTF-8 string
    args        : uint16 length-prefixed UTF-8 string (JSON-encoded)
"""

from __future__ import annotations

import struct
import zlib
from dataclasses import dataclass
from enum import Enum, IntEnum
from typing import Any, Dict, List, Optional, Tuple


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Two-byte magic that opens every frame.  0xC0EC is a mnemonic for "COEC(t)".
MAGIC_BYTES: bytes = b"\xC0\xEC"

# Current protocol revision.  Bump when the wire format changes in a
# backward-incompatible way so the engine can reject unsupported clients.
PROTOCOL_VERSION: int = 1

# Fixed sizes (in bytes) of each header / footer field.
_MAGIC_SIZE = 2
_VERSION_SIZE = 1
_TYPE_SIZE = 1
_LENGTH_SIZE = 4
_CRC_SIZE = 4
_HEADER_SIZE = _MAGIC_SIZE + _VERSION_SIZE + _TYPE_SIZE + _LENGTH_SIZE


# ---------------------------------------------------------------------------
# Message types
# ---------------------------------------------------------------------------

class MessageType(IntEnum):
    """Enumeration of the four message types the protocol supports."""

    SENSOR_READING = 0x01
    BATCH_READINGS = 0x02
    HEARTBEAT = 0x03
    CONTROL = 0x04


class MetricType(str, Enum):
    """Recognized spatiotemporal sensor metric families."""

    TEMPERATURE = "temperature"
    VELOCITY = "velocity"
    PRESSURE = "pressure"
    HUMIDITY = "humidity"
    AIR_QUALITY = "air_quality"
    WIND_SPEED = "wind_speed"


# ---------------------------------------------------------------------------
# Reading data class
# ---------------------------------------------------------------------------

@dataclass
class Reading:
    """A single georeferenced sensor observation.

    This is the fundamental unit of data flowing through the Convect
    pipeline. Every field is required; adapters are responsible for
    filling in defaults when the source data is sparse.

    Attributes:
        sensor_id: Unique identifier for the reporting sensor.
        lat:       WGS-84 latitude in decimal degrees [-90, 90].
        lon:       WGS-84 longitude in decimal degrees [-180, 180].
        timestamp: Observation time as milliseconds since Unix epoch.
        metric:    Name of the observed quantity (e.g. "temperature").
        value:     Numeric observation value in metric-appropriate units.
        quality:   Quality flag 0-255 (0 = unknown, 1 = good, 2+ = degraded).
    """

    sensor_id: str
    lat: float
    lon: float
    timestamp: int
    metric: str
    value: float
    quality: int = 1

    def __init__(
        self,
        sensor_id: str,
        lat: Optional[float] = None,
        lon: Optional[float] = None,
        timestamp: int = 0,
        metric: str = "temperature",
        value: float = 0.0,
        quality: int = 1,
        *,
        latitude: Optional[float] = None,
        longitude: Optional[float] = None,
        timestamp_ms: Optional[int] = None,
        metric_type: Optional[Any] = None,
    ) -> None:
        self.sensor_id = str(sensor_id)
        if latitude is not None:
            self.lat = float(latitude)
        elif lat is not None:
            self.lat = float(lat)
        else:
            self.lat = 0.0

        if longitude is not None:
            self.lon = float(longitude)
        elif lon is not None:
            self.lon = float(lon)
        else:
            self.lon = 0.0

        if timestamp_ms is not None:
            self.timestamp = int(timestamp_ms)
        else:
            self.timestamp = int(timestamp)

        if metric_type is not None:
            self.metric = str(metric_type.value if hasattr(metric_type, "value") else metric_type)
        else:
            self.metric = str(metric)

        self.value = float(value)
        self.quality = int(quality)

    @property
    def latitude(self) -> float:
        return self.lat

    @property
    def longitude(self) -> float:
        return self.lon

    @property
    def timestamp_ms(self) -> int:
        return self.timestamp


@dataclass(frozen=True)
class FrameHeader:
    version: int
    msg_type: MessageType
    length: int


# ---------------------------------------------------------------------------
# Protocol codec
# ---------------------------------------------------------------------------

class ConvectProtocol:
    """Encoder / decoder for the Convect binary wire protocol.

    All public methods are stateless class methods so callers do not need
    to instantiate the protocol object, but an instance is harmless and
    allows subclassing for custom extensions.
    """

    # ---- low-level helpers ------------------------------------------------

    @staticmethod
    def _encode_string(s: str) -> bytes:
        """Length-prefixed UTF-8 string: uint16 length + raw bytes."""
        encoded = s.encode("utf-8")
        if len(encoded) > 0xFFFF:
            raise ValueError(
                f"String too long for uint16 length prefix: {len(encoded)} bytes"
            )
        return struct.pack("!H", len(encoded)) + encoded

    @staticmethod
    def _decode_string(data: bytes, offset: int) -> tuple[str, int]:
        """Read a length-prefixed UTF-8 string starting at *offset*.

        Returns (decoded_string, new_offset).
        """
        (length,) = struct.unpack_from("!H", data, offset)
        offset += 2
        value = data[offset : offset + length].decode("utf-8")
        return value, offset + length

    # ---- reading payload --------------------------------------------------

    @classmethod
    def _encode_reading_payload(cls, reading: Reading) -> bytes:
        """Serialize a single Reading into its payload bytes (no framing)."""
        parts: list[bytes] = [
            cls._encode_string(reading.sensor_id),
            struct.pack("!d", reading.lat),
            struct.pack("!d", reading.lon),
            struct.pack("!q", reading.timestamp),
            cls._encode_string(reading.metric),
            struct.pack("!d", reading.value),
            struct.pack("!B", reading.quality),
        ]
        return b"".join(parts)

    @classmethod
    def _decode_reading_payload(cls, data: bytes, offset: int) -> tuple[Reading, int]:
        """Deserialize a single Reading from *data* starting at *offset*.

        Returns (Reading, new_offset).
        """
        sensor_id, offset = cls._decode_string(data, offset)
        (lat,) = struct.unpack_from("!d", data, offset); offset += 8
        (lon,) = struct.unpack_from("!d", data, offset); offset += 8
        (timestamp,) = struct.unpack_from("!q", data, offset); offset += 8
        metric, offset = cls._decode_string(data, offset)
        (value,) = struct.unpack_from("!d", data, offset); offset += 8
        (quality,) = struct.unpack_from("!B", data, offset); offset += 1
        return Reading(sensor_id, lat, lon, timestamp, metric, value, quality), offset

    # ---- frame construction -----------------------------------------------

    @classmethod
    def _build_frame(cls, msg_type: MessageType, payload: bytes) -> bytes:
        """Wrap a payload in a full wire frame (header + payload + CRC32)."""
        header = struct.pack(
            "!2sBBI",
            MAGIC_BYTES,
            PROTOCOL_VERSION,
            int(msg_type),
            len(payload),
        )
        frame_without_crc = header + payload
        crc = zlib.crc32(frame_without_crc) & 0xFFFFFFFF
        return frame_without_crc + struct.pack("!I", crc)

    # ---- public serialization API -----------------------------------------

    @classmethod
    def encode_reading(cls, reading: Reading) -> bytes:
        """Serialize a single sensor reading into a complete wire frame."""
        payload = cls._encode_reading_payload(reading)
        return cls._build_frame(MessageType.SENSOR_READING, payload)

    @classmethod
    def encode_batch(cls, readings: List[Reading]) -> bytes:
        """Serialize a batch of readings into a single wire frame.

        Using batches amortizes the per-frame overhead and lets the engine
        process groups of readings atomically.
        """
        parts: list[bytes] = [struct.pack("!I", len(readings))]
        for r in readings:
            parts.append(cls._encode_reading_payload(r))
        return cls._build_frame(MessageType.BATCH_READINGS, b"".join(parts))

    @classmethod
    def encode_heartbeat(cls, timestamp_ms: int) -> bytes:
        """Encode a heartbeat frame carrying the given timestamp."""
        payload = struct.pack("!q", timestamp_ms)
        return cls._build_frame(MessageType.HEARTBEAT, payload)

    @classmethod
    def encode_control(cls, command: str, args: str = "{}") -> bytes:
        """Encode a control message with a command string and JSON args."""
        payload = cls._encode_string(command) + cls._encode_string(args)
        return cls._build_frame(MessageType.CONTROL, payload)

    # ---- public deserialization API ---------------------------------------

    @classmethod
    def decode_frame(cls, data: bytes) -> dict:
        """Decode a complete wire frame from raw bytes.

        Returns a dict with keys:
            "type"    : MessageType
            "payload" : decoded content (Reading, list[Reading], int, or dict)

        Raises ValueError on magic mismatch, version mismatch, CRC failure,
        or truncated data.
        """
        if len(data) < _HEADER_SIZE + _CRC_SIZE:
            raise ValueError(
                f"Frame too short: need at least {_HEADER_SIZE + _CRC_SIZE} bytes, "
                f"got {len(data)}"
            )

        # -- header --
        magic = data[:_MAGIC_SIZE]
        if magic != MAGIC_BYTES:
            raise ValueError(
                f"Bad magic: expected 0x{MAGIC_BYTES.hex()}, got 0x{magic.hex()}"
            )

        (version,) = struct.unpack_from("!B", data, _MAGIC_SIZE)
        if version != PROTOCOL_VERSION:
            raise ValueError(
                f"Unsupported protocol version: {version} "
                f"(this client speaks version {PROTOCOL_VERSION})"
            )

        (msg_type_raw,) = struct.unpack_from("!B", data, _MAGIC_SIZE + _VERSION_SIZE)
        try:
            msg_type = MessageType(msg_type_raw)
        except ValueError:
            raise ValueError(f"Unknown message type: 0x{msg_type_raw:02X}")

        (payload_len,) = struct.unpack_from("!I", data, _MAGIC_SIZE + _VERSION_SIZE + _TYPE_SIZE)

        expected_total = _HEADER_SIZE + payload_len + _CRC_SIZE
        if len(data) < expected_total:
            raise ValueError(
                f"Truncated frame: header says {expected_total} bytes, "
                f"got {len(data)}"
            )

        payload_start = _HEADER_SIZE
        payload_end = payload_start + payload_len

        # -- CRC verification --
        frame_without_crc = data[:payload_end]
        (crc_received,) = struct.unpack_from("!I", data, payload_end)
        crc_computed = zlib.crc32(frame_without_crc) & 0xFFFFFFFF
        if crc_received != crc_computed:
            raise ValueError(
                f"CRC32 mismatch: received 0x{crc_received:08X}, "
                f"computed 0x{crc_computed:08X}"
            )

        payload_data = data[payload_start:payload_end]

        # -- payload decode --
        if msg_type == MessageType.SENSOR_READING:
            reading, _ = cls._decode_reading_payload(payload_data, 0)
            return {"type": msg_type, "payload": reading}

        elif msg_type == MessageType.BATCH_READINGS:
            (count,) = struct.unpack_from("!I", payload_data, 0)
            offset = 4
            readings: list[Reading] = []
            for _ in range(count):
                reading, offset = cls._decode_reading_payload(payload_data, offset)
                readings.append(reading)
            return {"type": msg_type, "payload": readings}

        elif msg_type == MessageType.HEARTBEAT:
            (ts,) = struct.unpack_from("!q", payload_data, 0)
            return {"type": msg_type, "payload": ts}

        elif msg_type == MessageType.CONTROL:
            command, off = cls._decode_string(payload_data, 0)
            args, _ = cls._decode_string(payload_data, off)
            return {"type": msg_type, "payload": {"command": command, "args": args}}

        # Unreachable if MessageType covers all cases, but defensive.
        raise ValueError(f"Unhandled message type: {msg_type}")  # pragma: no cover

    # ---- compatibility aliases ---------------------------------------------

    @classmethod
    def serialize_reading(cls, reading: Reading) -> bytes:
        return cls.encode_reading(reading)

    @classmethod
    def serialize_batch(cls, readings: List[Reading]) -> bytes:
        return cls.encode_batch(readings)

    @classmethod
    def serialize_heartbeat(cls, sequence_num: int = 0) -> bytes:
        return cls.encode_heartbeat(sequence_num)

    @classmethod
    def deserialize_reading(cls, payload: bytes) -> Reading:
        r, _ = cls._decode_reading_payload(payload, 0)
        return r

    @classmethod
    def deserialize_batch(cls, payload: bytes) -> List[Reading]:
        (count,) = struct.unpack_from("!I", payload, 0)
        offset = 4
        res: List[Reading] = []
        for _ in range(count):
            r, offset = cls._decode_reading_payload(payload, offset)
            res.append(r)
        return res

    @classmethod
    def deserialize_heartbeat(cls, payload: bytes) -> int:
        (ts,) = struct.unpack_from("!q", payload, 0)
        return ts

    @classmethod
    def deserialize_frame(cls, data: bytes) -> Tuple[FrameHeader, bytes]:
        if len(data) < _HEADER_SIZE + _CRC_SIZE:
            raise ValueError(f"Buffer too short: {len(data)}")

        magic = data[:_MAGIC_SIZE]
        if magic != MAGIC_BYTES:
            raise ValueError(f"Invalid magic: expected 0x{MAGIC_BYTES.hex()}, got 0x{magic.hex()}")

        (version,) = struct.unpack_from("!B", data, _MAGIC_SIZE)
        (msg_type_raw,) = struct.unpack_from("!B", data, _MAGIC_SIZE + _VERSION_SIZE)
        msg_type = MessageType(msg_type_raw)
        (payload_len,) = struct.unpack_from("!I", data, _MAGIC_SIZE + _VERSION_SIZE + _TYPE_SIZE)

        expected_total = _HEADER_SIZE + payload_len + _CRC_SIZE
        if len(data) < expected_total:
            raise ValueError(f"Buffer too short for frame: expected {expected_total}, got {len(data)}")

        payload_start = _HEADER_SIZE
        payload_end = payload_start + payload_len

        frame_without_crc = data[:payload_end]
        (crc_received,) = struct.unpack_from("!I", data, payload_end)
        crc_computed = zlib.crc32(frame_without_crc) & 0xFFFFFFFF
        if crc_received != crc_computed:
            raise ValueError(f"CRC32 mismatch: {crc_received} vs {crc_computed}")

        header = FrameHeader(version=version, msg_type=msg_type, length=payload_len)
        return header, data[payload_start:payload_end]
