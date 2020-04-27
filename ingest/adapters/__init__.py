"""
convect.ingest.adapters - Source data format adapters.

Copyright 2026 Convect Authors. All rights reserved.
SPDX-License-Identifier: Apache-2.0
"""

from ingest.adapters.base import BaseAdapter
from ingest.adapters.geojson_adapter import GeoJSONAdapter
from ingest.adapters.csv_adapter import CSVAdapter
from ingest.adapters.noaa_adapter import NOAAIsdAdapter

__all__ = [
    "BaseAdapter",
    "GeoJSONAdapter",
    "CSVAdapter",
    "NOAAIsdAdapter",
]
