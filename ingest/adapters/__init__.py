"""
convect.ingest.adapters - Source data format adapters.

Copyright 2026 Convect Authors. All rights reserved.
SPDX-License-Identifier: Apache-2.0
"""

from ingest.adapters.base import BaseAdapter
from ingest.adapters.geojson_adapter import GeoJSONAdapter
from ingest.adapters.csv_adapter import CSVAdapter
from ingest.adapters.noaa_adapter import NOAAIsdAdapter
from ingest.adapters.netcdf_adapter import NetCDFGridAdapter
from ingest.adapters.ais_marine_adapter import AISMarineAdapter
from ingest.adapters.adsb_aviation_adapter import ADSBAviationAdapter

__all__ = [
    "BaseAdapter",
    "GeoJSONAdapter",
    "CSVAdapter",
    "NOAAIsdAdapter",
    "NetCDFGridAdapter",
    "AISMarineAdapter",
    "ADSBAviationAdapter",
]
