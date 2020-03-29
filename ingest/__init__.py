"""
convect.ingest - Data ingestion layer for the Convect geospatial stream engine.

This package provides:
- A binary wire protocol for feeding sensor readings to the X10 engine
- A reconnecting TCP client with batching and stats tracking
- Format adapters for GeoJSON, CSV, and NOAA ISD data
- Synthetic data generators for testing and benchmarking

Typical usage:
    from ingest.client import ConvectIngestClient
    from ingest.adapters.csv_adapter import CsvAdapter

    adapter = CsvAdapter(column_map={"latitude": "lat", "longitude": "lon"})
    with ConvectIngestClient("localhost", 9100) as client:
        for reading in adapter.parse("sensors.csv"):
            client.send_reading(reading)
"""

from ingest.protocol import (
    ConvectProtocol,
    MessageType,
    Reading,
    MAGIC_BYTES,
    PROTOCOL_VERSION,
)
from ingest.client import ConvectIngestClient

__all__ = [
    "ConvectProtocol",
    "MessageType",
    "Reading",
    "ConvectIngestClient",
    "MAGIC_BYTES",
    "PROTOCOL_VERSION",
]

__version__ = "0.1.0"
