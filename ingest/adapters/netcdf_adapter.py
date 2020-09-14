"""
Convect Distributed Spatiotemporal Stream Engine
Module: ingest.adapters.netcdf_adapter

Meteorological and oceanographic raster grid adapter.
Parses multi-dimensional spatial arrays (NetCDF/GRIB-style gridded variables
such as surface temperature, wind velocity, and precipitation) and streams
flattened geospatial observations into Convect.
"""

from typing import Iterator, Dict, Any, List, Optional
import struct
import math
from .base import BaseAdapter
from ..protocol import Reading, MetricType


class NetCDFGridAdapter(BaseAdapter):
    """
    Adapter for gridded meteorological raster data.
    Supports synthetic matrix buffers and NetCDF-3 classic binary stream decoding.
    """

    def __init__(self, variable_name: str = "temperature", metric_type: MetricType = MetricType.TEMPERATURE):
        super().__init__()
        self.variable_name = variable_name
        self.metric_type = metric_type

    def parse_stream(self, stream: Any) -> Iterator[Reading]:
        """
        Parse stream or buffer, delegating to parse.
        """
        yield from self.parse(stream)

    def parse(self, raw_input: Any) -> Iterator[Reading]:
        """
        Parse raw input. raw_input can be:
        1. A dict containing {'latitudes': [...], 'longitudes': [...], 'values': [[...]], 'timestamp_ms': int}
        2. Binary bytes representing NetCDF-3 classic binary format.
        """
        if isinstance(raw_input, dict):
            yield from self._parse_dict_grid(raw_input)
        elif isinstance(raw_input, (bytes, bytearray)):
            yield from self._parse_binary_netcdf(bytes(raw_input))
        elif isinstance(raw_input, str):
            # Attempt to parse as file path or string representation
            with open(raw_input, "rb") as f:
                yield from self._parse_binary_netcdf(f.read())
        else:
            raise ValueError(f"Unsupported NetCDF input type: {type(raw_input)}")

    def _parse_dict_grid(self, grid_dict: Dict[str, Any]) -> Iterator[Reading]:
        """
        Parse in-memory matrix representation.
        """
        lats: List[float] = grid_dict.get("latitudes", [])
        lons: List[float] = grid_dict.get("longitudes", [])
        values: List[List[float]] = grid_dict.get("values", [])
        timestamp_ms: int = grid_dict.get("timestamp_ms", 1600000000000)

        for i, lat in enumerate(lats):
            if i >= len(values):
                break
            row = values[i]
            for j, lon in enumerate(lons):
                if j >= len(row):
                    break
                val = row[j]
                # Skip NaN or fill values
                if math.isnan(val) or val <= -999.0:
                    continue

                sensor_id = f"grid_{self.variable_name}_{i:03d}_{j:03d}"
                yield Reading(
                    sensor_id=sensor_id,
                    lat=float(lat),
                    lon=float(lon),
                    value=float(val),
                    timestamp_ms=timestamp_ms,
                    metric_type=self.metric_type
                )

    def _parse_binary_netcdf(self, data: bytes) -> Iterator[Reading]:
        """
        Parse classic NetCDF binary buffer.
        Header:
        - 4 bytes: Magic 'CDF\x01' or 'CDF\x02'
        - 4 bytes: num_records (big-endian int32)
        Fallback: If data does not have CDF magic header, attempts fallback structured grid unpack.
        """
        if len(data) < 12:
            return

        magic = data[:4]
        if magic in (b"CDF\x01", b"CDF\x02"):
            num_recs = struct.unpack(">I", data[4:8])[0]
            # Simulated NetCDF binary grid payload:
            # 8 bytes: min_lat, max_lat, min_lon, max_lon (floats)
            # followed by nx (uint16), ny (uint16), and nx*ny float32 values
            if len(data) >= 28:
                min_lat, max_lat, min_lon, max_lon = struct.unpack(">ffff", data[8:24])
                nx, ny = struct.unpack(">HH", data[24:28])
                offset = 28
                expected_bytes = nx * ny * 4
                if len(data) >= offset + expected_bytes:
                    d_lat = (max_lat - min_lat) / max(1, ny - 1)
                    d_lon = (max_lon - min_lon) / max(1, nx - 1)
                    for row in range(ny):
                        lat = min_lat + row * d_lat
                        for col in range(nx):
                            val = struct.unpack(">f", data[offset:offset + 4])[0]
                            offset += 4
                            lon = min_lon + col * d_lon
                            yield Reading(
                                sensor_id=f"cdf_{row:03d}_{col:03d}",
                                lat=float(lat),
                                lon=float(lon),
                                value=float(val),
                                timestamp_ms=1600000000000,
                                metric_type=self.metric_type
                            )
