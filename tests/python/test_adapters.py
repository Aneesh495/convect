"""
tests.python.test_adapters - Unit tests for GeoJSON, CSV, and NOAA ISD format adapters.

Copyright 2026 Convect Authors. All rights reserved.
SPDX-License-Identifier: Apache-2.0
"""

import gzip
import io
import json
import unittest
from ingest.adapters import (
    CSVAdapter,
    GeoJSONAdapter,
    NOAAIsdAdapter,
    NetCDFGridAdapter,
    AISMarineAdapter,
    ADSBAviationAdapter,
)


class TestAdapters(unittest.TestCase):

    def test_geojson_feature_collection(self) -> None:
        doc = {
            "type": "FeatureCollection",
            "features": [
                {
                    "type": "Feature",
                    "geometry": {"type": "Point", "coordinates": [-122.4194, 37.7749]},
                    "properties": {
                        "sensor_id": "sf_downtown",
                        "timestamp": 1731580000000,
                        "value": 18.5,
                        "quality": 95,
                    },
                },
                {
                    "type": "Feature",
                    "geometry": {"type": "Point", "coordinates": [-122.2711, 37.8044]},
                    "properties": {
                        "sensor_id": "oakland_port",
                        "timestamp": 1731580001000,
                        "value": 16.2,
                        "quality": 90,
                    },
                },
            ],
        }

        stream = io.StringIO(json.dumps(doc))
        adapter = GeoJSONAdapter()
        readings = list(adapter.parse_stream(stream))

        self.assertEqual(len(readings), 2)
        self.assertEqual(readings[0].sensor_id, "sf_downtown")
        self.assertAlmostEqual(readings[0].latitude, 37.7749)
        self.assertAlmostEqual(readings[0].longitude, -122.4194)
        self.assertAlmostEqual(readings[0].value, 18.5)

        self.assertEqual(readings[1].sensor_id, "oakland_port")
        self.assertAlmostEqual(readings[1].latitude, 37.8044)

    def test_geojson_line_delimited(self) -> None:
        lines = [
            json.dumps({
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [-74.0060, 40.7128]},
                "properties": {"sensor_id": "nyc_01", "value": 22.1, "timestamp": 1731580000000},
            }),
            json.dumps({
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [-71.0589, 42.3601]},
                "properties": {"sensor_id": "bos_01", "value": 19.4, "timestamp": 1731580000000},
            }),
        ]
        stream = io.StringIO("\n".join(lines))
        adapter = GeoJSONAdapter()
        readings = list(adapter.parse_stream(stream))
        self.assertEqual(len(readings), 2)
        self.assertEqual(readings[0].sensor_id, "nyc_01")
        self.assertEqual(readings[1].sensor_id, "bos_01")

    def test_csv_adapter_standard(self) -> None:
        csv_data = (
            "sensor_id,latitude,longitude,timestamp,value\n"
            "s1,34.05,-118.24,1731580000000,25.5\n"
            "s2,36.16,-115.15,1731580001000,29.1\n"
        )
        adapter = CSVAdapter()
        readings = list(adapter.parse_stream(io.StringIO(csv_data)))
        self.assertEqual(len(readings), 2)
        self.assertEqual(readings[0].sensor_id, "s1")
        self.assertAlmostEqual(readings[0].latitude, 34.05)
        self.assertAlmostEqual(readings[1].value, 29.1)

    def test_csv_adapter_bad_rows_skipped(self) -> None:
        csv_data = (
            "sensor_id,latitude,longitude,timestamp,value\n"
            "s1,34.05,-118.24,1731580000000,25.5\n"
            "s_bad,invalid_lat,-118.24,1731580000000,25.5\n"
            "s_out_of_bounds,195.0,-118.24,1731580000000,25.5\n"
            "s2,36.16,-115.15,1731580001000,29.1\n"
        )
        adapter = CSVAdapter()
        readings = list(adapter.parse_stream(io.StringIO(csv_data)))
        self.assertEqual(len(readings), 2)
        stats = adapter.get_stats()
        self.assertEqual(stats["valid"], 2)
        self.assertGreater(stats["rejected"], 0)

    def test_noaa_isd_line_parsing(self) -> None:
        # Construct synthetic valid NOAA ISD record with fixed offsets
        # Length 4 chars, USAF 6 chars, WBAN 5 chars, Date 8 chars, Time 4 chars, source 1 char,
        # Lat 6 chars, Lon 7 chars ... Air Temp at pos 87-92
        header_part = "0050" + "724940" + "23234" + "20261114" + "1200" + "4"
        coord_part = "+37619" + "-122375" + "FM-15" + "+0003" + "KSFO " + "V020"
        met_part = "270" + "1" + "N" + "0050" + "1" + "99999" + "9" + "999999" + "9"
        # Pad up to offset 87 where air temperature starts in ISD format
        prefix = header_part + coord_part + met_part
        filler = " " * (87 - len(prefix))
        temp_part = "+0185" + "1"  # +18.5 deg C, quality 1 (passed)
        isd_line = prefix + filler + temp_part + " " * 30

        adapter = NOAAIsdAdapter(target_metric="air_temperature")
        readings = list(adapter.parse_stream([isd_line]))
        self.assertEqual(len(readings), 1)
        r = readings[0]
        self.assertEqual(r.sensor_id, "NOAA_724940_23234")
        self.assertAlmostEqual(r.latitude, 37.619, places=3)
        self.assertAlmostEqual(r.longitude, -122.375, places=3)
        self.assertAlmostEqual(r.value, 18.5, places=1)
        self.assertEqual(r.quality, 100)

    def test_netcdf_dict_grid_parsing(self) -> None:
        grid_data = {
            "latitudes": [37.7, 37.8],
            "longitudes": [-122.5, -122.4],
            "values": [
                [15.2, 16.1],
                [14.8, 15.9],
            ],
            "timestamp_ms": 1731580000000,
        }
        adapter = NetCDFGridAdapter(variable_name="temp2m")
        readings = list(adapter.parse(grid_data))
        self.assertEqual(len(readings), 4)
        self.assertEqual(readings[0].sensor_id, "grid_temp2m_000_000")
        self.assertAlmostEqual(readings[0].latitude, 37.7)
        self.assertAlmostEqual(readings[0].longitude, -122.5)
        self.assertAlmostEqual(readings[0].value, 15.2)

    def test_ais_marine_adapter_json_and_csv(self) -> None:
        ais_json = json.dumps([
            {"mmsi": 367123450, "lat": 37.795, "lon": -122.390, "sog": 12.4, "timestamp": 1731580000000},
            {"mmsi": 367999999, "lat": 37.810, "lon": -122.420, "sog": 0.2, "timestamp": 1731580001000},
        ])
        adapter = AISMarineAdapter()
        readings = list(adapter.parse(ais_json))
        self.assertEqual(len(readings), 2)
        self.assertEqual(readings[0].sensor_id, "vessel_367123450")
        self.assertAlmostEqual(readings[0].latitude, 37.795)
        self.assertAlmostEqual(readings[0].value, 12.4)

        # Test CSV format
        csv_line = "367111222,37.805,-122.410,15.8,1731580002000"
        csv_readings = list(adapter.parse(csv_line))
        self.assertEqual(len(csv_readings), 1)
        self.assertEqual(csv_readings[0].sensor_id, "vessel_367111222")
        self.assertAlmostEqual(csv_readings[0].value, 15.8)

    def test_adsb_aviation_adapter(self) -> None:
        # Test JSON aircraft list
        dump1090_json = json.dumps({
            "aircraft": [
                {"hex": "A1B2C3", "lat": 37.618, "lon": -122.375, "speed": 240.0, "alt_baro": 4500.0},
                {"hex": "C4D5E6", "lat": 37.700, "lon": -122.300, "speed": 180.0, "alt_baro": 2200.0},
            ]
        })
        adapter = ADSBAviationAdapter()
        readings = list(adapter.parse(dump1090_json))
        self.assertEqual(len(readings), 2)
        self.assertEqual(readings[0].sensor_id, "flight_A1B2C3")
        self.assertAlmostEqual(readings[0].latitude, 37.618)
        self.assertAlmostEqual(readings[0].value, 240.0)

        # Test SBS-1 BaseStation line
        sbs_line = "MSG,3,1,1,A1B2C3,1,2026/11/14,10:00:00.000,2026/11/14,10:00:00.000,,5000,,,37.620,-122.380,,,0,0,0,0"
        sbs_readings = list(adapter.parse(sbs_line))
        self.assertEqual(len(sbs_readings), 1)
        self.assertEqual(sbs_readings[0].sensor_id, "flight_A1B2C3")
        self.assertAlmostEqual(sbs_readings[0].value, 5000.0)


if __name__ == "__main__":
    unittest.main()
