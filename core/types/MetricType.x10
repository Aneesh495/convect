package convect.core.types;

/**
 * MetricType enumerates standard environmental, meteorological, and air-quality metrics.
 *
 * Provides physical unit descriptors, plausible validation ranges, and integer codes
 * for compact binary wire transfer and X10 struct packing.
 *
 * Copyright 2026 Convect Authors. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
public class MetricType {

    public static val TEMPERATURE:Int   = 1n; /* Celsius */
    public static val HUMIDITY:Int      = 2n; /* Relative % */
    public static val PRESSURE:Int      = 3n; /* hPa */
    public static val PM25:Int          = 4n; /* ug/m^3 */
    public static val PM10:Int          = 5n; /* ug/m^3 */
    public static val CO2:Int           = 6n; /* ppm */
    public static val WIND_SPEED:Int    = 7n; /* m/s */
    public static val OZONE:Int         = 8n; /* ppb */
    public static val RADIATION:Int     = 9n; /* uSv/h */

    public static def name(code:Int):String {
        switch (code) {
            case TEMPERATURE: return "temperature";
            case HUMIDITY:    return "humidity";
            case PRESSURE:    return "pressure";
            case PM25:        return "pm25";
            case PM10:        return "pm10";
            case CO2:         return "co2";
            case WIND_SPEED:  return "wind_speed";
            case OZONE:       return "ozone";
            case RADIATION:   return "radiation";
            default:          return "custom_metric_" + code;
        }
    }

    public static def unit(code:Int):String {
        switch (code) {
            case TEMPERATURE: return "degC";
            case HUMIDITY:    return "%";
            case PRESSURE:    return "hPa";
            case PM25:        return "ug/m3";
            case PM10:        return "ug/m3";
            case CO2:         return "ppm";
            case WIND_SPEED:  return "m/s";
            case OZONE:       return "ppb";
            case RADIATION:   return "uSv/h";
            default:          return "units";
        }
    }

    public static def isValid(code:Int, val:Double):Boolean {
        switch (code) {
            case TEMPERATURE: return val >= -80.0 && val <= 70.0;
            case HUMIDITY:    return val >= 0.0 && val <= 100.0;
            case PRESSURE:    return val >= 800.0 && val <= 1100.0;
            case PM25:        return val >= 0.0 && val <= 1000.0;
            case PM10:        return val >= 0.0 && val <= 2000.0;
            case CO2:         return val >= 200.0 && val <= 50000.0;
            case WIND_SPEED:  return val >= 0.0 && val <= 150.0;
            case OZONE:       return val >= 0.0 && val <= 1000.0;
            case RADIATION:   return val >= 0.0 && val <= 500.0;
            default:          return true;
        }
    }
}
