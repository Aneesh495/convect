"""
convect.core.runtime.X10RuntimeEmulator - High-fidelity multi-place PGAS runtime simulator.

Simulates the IBM X10 Partitioned Global Address Space (PGAS) concurrency model
(Places, async activities, finish synchronization barriers, at-place shifts)
and interfaces directly with the compiled C spatial indexing engine via ctypes.

Enables full out-of-the-box local execution, testing, and continuous integration
without requiring a pre-installed legacy IBM X10 compiler toolchain.

Copyright 2026 Convect Authors. All rights reserved.
SPDX-License-Identifier: Apache-2.0
"""

from __future__ import annotations

import ctypes
import os
import platform
import threading
import time
from dataclasses import dataclass
from typing import Any, Callable, Dict, List, Optional, Tuple

from ingest.protocol import Reading


# ---------------------------------------------------------------------------
# C Spatial Index FFI Bindings
# ---------------------------------------------------------------------------

class CSpatialBbox(ctypes.Structure):
    _fields_ = [
        ("min_lat", ctypes.c_double),
        ("min_lon", ctypes.c_double),
        ("max_lat", ctypes.c_double),
        ("max_lon", ctypes.c_double),
    ]


class CSpatialEntry(ctypes.Structure):
    _fields_ = [
        ("id", ctypes.c_uint64),
        ("bbox", CSpatialBbox),
        ("payload", ctypes.c_void_p),
    ]


class CSpatialResult(ctypes.Structure):
    _fields_ = [
        ("id", ctypes.c_uint64),
        ("distance", ctypes.c_double),
        ("payload", ctypes.c_void_p),
    ]


class CSpatialResultSet(ctypes.Structure):
    _fields_ = [
        ("results", ctypes.POINTER(CSpatialResult)),
        ("count", ctypes.c_size_t),
        ("capacity", ctypes.c_size_t),
    ]


def load_spatial_library() -> Optional[ctypes.CDLL]:
    """Dynamically load libconvect_spatial shared object."""
    ext = "dylib" if platform.system() == "Darwin" else "so"
    # Search common build paths
    base_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    candidate_paths = [
        os.path.join(base_dir, "index", "build", f"libconvect_spatial.{ext}"),
        os.path.join(base_dir, "build", f"libconvect_spatial.{ext}"),
    ]

    for p in candidate_paths:
        if os.path.exists(p):
            try:
                lib = ctypes.CDLL(p)
                # Configure signatures
                lib.rtree_create.argtypes = [ctypes.c_int, ctypes.c_int]
                lib.rtree_create.restype = ctypes.c_void_p

                lib.rtree_destroy.argtypes = [ctypes.c_void_p]
                lib.rtree_destroy.restype = None

                lib.rtree_insert.argtypes = [ctypes.c_void_p, CSpatialEntry]
                lib.rtree_insert.restype = ctypes.c_int

                lib.rtree_query_range.argtypes = [
                    ctypes.c_void_p,
                    ctypes.POINTER(CSpatialBbox),
                    ctypes.POINTER(CSpatialResultSet),
                ]
                lib.rtree_query_range.restype = ctypes.c_int

                lib.result_set_init.argtypes = [ctypes.POINTER(CSpatialResultSet), ctypes.c_size_t]
                lib.result_set_init.restype = ctypes.c_int

                lib.result_set_free.argtypes = [ctypes.POINTER(CSpatialResultSet)]
                lib.result_set_free.restype = None

                lib.hilbert_from_latlon.argtypes = [ctypes.c_double, ctypes.c_double, ctypes.c_uint32]
                lib.hilbert_from_latlon.restype = ctypes.c_uint64

                lib.point_distance_haversine.argtypes = [
                    ctypes.c_double, ctypes.c_double,
                    ctypes.c_double, ctypes.c_double,
                ]
                lib.point_distance_haversine.restype = ctypes.c_double

                return lib
            except Exception:
                pass
    return None


# ---------------------------------------------------------------------------
# X10 Place Concurrency Model
# ---------------------------------------------------------------------------

class X10Place:
    """Represents an isolated memory partition in X10's PGAS model."""

    def __init__(self, place_id: int, lib: Optional[ctypes.CDLL] = None) -> None:
        self.place_id = place_id
        self.lib = lib
        self.readings: List[Reading] = []
        self.wal_log: List[Reading] = []
        self.lock = threading.Lock()
        self.rtree_ptr = lib.rtree_create(4, 16) if lib else None

    def __del__(self) -> None:
        if self.lib and self.rtree_ptr:
            try:
                self.lib.rtree_destroy(self.rtree_ptr)
            except Exception:
                pass

    def ingest(self, reading: Reading) -> None:
        with self.lock:
            self.wal_log.append(reading)
            self.readings.append(reading)

            if self.lib and self.rtree_ptr:
                entry = CSpatialEntry()
                entry.id = int(reading.timestamp % 1000000)
                entry.bbox = CSpatialBbox(reading.latitude, reading.longitude, reading.latitude, reading.longitude)
                entry.payload = None
                self.lib.rtree_insert(self.rtree_ptr, entry)

    def query_bbox(self, min_lat: float, min_lon: float, max_lat: float, max_lon: float) -> List[Reading]:
        with self.lock:
            # Fallback Python spatial filter or C R-tree
            matches = []
            for r in self.readings:
                if min_lat <= r.latitude <= max_lat and min_lon <= r.longitude <= max_lon:
                    matches.append(r)
            return matches


class X10RuntimeCluster:
    """Coordinates a cluster of X10 Places and routes work across them."""

    def __init__(self, num_places: int = 4, tile_order: int = 8) -> None:
        self.num_places = num_places
        self.tile_order = tile_order
        self.lib = load_spatial_library()
        self.places = [X10Place(p, self.lib) for p in range(num_places)]

    def route_reading_to_place(self, reading: Reading) -> int:
        """Route reading to place using Hilbert space-filling curve partition."""
        if self.lib:
            h_idx = self.lib.hilbert_from_latlon(reading.latitude, reading.longitude, self.tile_order)
        else:
            # Simple fallback hash
            h_idx = hash((round(reading.latitude, 2), round(reading.longitude, 2))) & 0xFFFFFF

        total_cells = 1 << (2 * self.tile_order)
        cells_per_place = total_cells // self.num_places
        place_id = min(self.num_places - 1, int(h_idx // cells_per_place))
        return place_id

    def ingest_reading(self, reading: Reading) -> int:
        """Simulate X10 'at(targetPlace) async' ingestion."""
        target_p = self.route_reading_to_place(reading)
        self.places[target_p].ingest(reading)
        return target_p

    def ingest_batch(self, readings: List[Reading]) -> int:
        for r in readings:
            self.ingest_reading(r)
        return len(readings)

    def query_range(self, min_lat: float, min_lon: float, max_lat: float, max_lon: float) -> List[Reading]:
        """Simulate X10 'finish { for(p in Place.places()) at(p) async ... }'."""
        consolidated: List[Reading] = []
        threads = []
        results: Dict[int, List[Reading]] = {}

        def query_worker(p: X10Place) -> None:
            res = p.query_bbox(min_lat, min_lon, max_lat, max_lon)
            results[p.place_id] = res

        for place in self.places:
            t = threading.Thread(target=query_worker, args=(place,))
            threads.append(t)
            t.start()

        for t in threads:
            t.join()

        for pid in sorted(results.keys()):
            consolidated.extend(results[pid])

        return consolidated
