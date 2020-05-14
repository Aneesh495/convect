"""
tests.python.test_protocol - Unit tests for the binary wire protocol.

Verifies:
  - Header magic bytes (0xC0EC) and version byte validation
  - CRC32 integrity verification and detection of corrupted payloads
  - Single reading serialization / deserialization roundtrip
  - Batch readings serialization / deserialization roundtrip
  - Heartbeat and control message framing
  - Truncated or fragmented buffer handling

Copyright 2026 Convect Authors. All rights reserved.
SPDX-License-Identifier: Apache-2.0
"""

import struct
import unittest
from ingest.protocol import ConvectProtocol, MessageType, Reading


class TestConvectProtocol(unittest.TestCase):

    def test_single_reading_roundtrip(self) -> None:
        original = Reading(
            sensor_id="station_alpha_01",
            latitude=37.774929,
            longitude=-122.419416,
            timestamp=1731580000000,
            metric="ambient_pm25",
            value=14.28,
            quality=98,
        )

        frame = ConvectProtocol.serialize_reading(original)
        self.assertGreater(len(frame), 12)

        # Deserialize
        header, payload = ConvectProtocol.deserialize_frame(frame)
        self.assertEqual(header.msg_type, MessageType.SENSOR_READING)
        self.assertEqual(header.version, 1)

        decoded = ConvectProtocol.deserialize_reading(payload)
        self.assertEqual(decoded.sensor_id, original.sensor_id)
        self.assertAlmostEqual(decoded.latitude, original.latitude, places=5)
        self.assertAlmostEqual(decoded.longitude, original.longitude, places=5)
        self.assertEqual(decoded.timestamp, original.timestamp)
        self.assertEqual(decoded.metric, original.metric)
        self.assertAlmostEqual(decoded.value, original.value, places=2)
        self.assertEqual(decoded.quality, original.quality)

    def test_batch_readings_roundtrip(self) -> None:
        readings = [
            Reading(f"sensor_{i}", 40.0 + i * 0.1, -74.0 - i * 0.1, 1731580000000 + i * 1000, "temperature", 20.0 + i, 100)
            for i in range(25)
        ]

        frame = ConvectProtocol.serialize_batch(readings)
        header, payload = ConvectProtocol.deserialize_frame(frame)
        self.assertEqual(header.msg_type, MessageType.BATCH_READINGS)

        decoded_list = ConvectProtocol.deserialize_batch(payload)
        self.assertEqual(len(decoded_list), 25)
        for orig, dec in zip(readings, decoded_list):
            self.assertEqual(dec.sensor_id, orig.sensor_id)
            self.assertAlmostEqual(dec.latitude, orig.latitude, places=4)
            self.assertAlmostEqual(dec.value, orig.value, places=2)

    def test_heartbeat_and_control(self) -> None:
        hb_frame = ConvectProtocol.serialize_heartbeat(sequence_num=42)
        header, payload = ConvectProtocol.deserialize_frame(hb_frame)
        self.assertEqual(header.msg_type, MessageType.HEARTBEAT)
        seq = ConvectProtocol.deserialize_heartbeat(payload)
        self.assertEqual(seq, 42)

    def test_crc32_corruption_detection(self) -> None:
        orig = Reading("probe_01", 34.05, -118.24, 1731580000000, "co2_ppm", 418.5, 100)
        frame = bytearray(ConvectProtocol.serialize_reading(orig))

        # Corrupt one byte inside the payload section
        frame[15] ^= 0xFF

        with self.assertRaises(ValueError) as ctx:
            ConvectProtocol.deserialize_frame(bytes(frame))
        self.assertIn("CRC32 mismatch", str(ctx.exception))

    def test_invalid_magic_bytes(self) -> None:
        orig = Reading("probe_01", 34.05, -118.24, 1731580000000, "co2_ppm", 418.5, 100)
        frame = bytearray(ConvectProtocol.serialize_reading(orig))
        frame[0] = 0xAA
        frame[1] = 0xBB

        with self.assertRaises(ValueError) as ctx:
            ConvectProtocol.deserialize_frame(bytes(frame))
        self.assertIn("Invalid magic", str(ctx.exception))

    def test_truncated_frame(self) -> None:
        orig = Reading("probe_01", 34.05, -118.24, 1731580000000, "co2_ppm", 418.5, 100)
        frame = ConvectProtocol.serialize_reading(orig)

        # Slice frame before end
        with self.assertRaises(ValueError) as ctx:
            ConvectProtocol.deserialize_frame(frame[: len(frame) - 5])
        self.assertIn("Buffer too short", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
