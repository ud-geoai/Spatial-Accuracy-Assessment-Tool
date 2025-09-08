# Spatial Accuracy Assessment Tool

This R script provides functions for spatially explicit accuracy assessment of categorical classification rasters. It computes user’s accuracy (UA), producer’s accuracy (PA), F1-score, and area-based summaries for a target class, and produces publication-ready facet maps. The tool is designed for geospatial analysis with the terra package.

## Contents

- **spatial_accuracy** – Faceted map of classification layers with per-layer metrics.
- **calculate_area** – Area statistics for the target class inside/outside polygons.

## Requirements

- **R (≥ 4.0 recommended)**
- **terra, dplyr, ggplot2, tidyr, sf packages**

---

### Function: spatial_accuracy

**Description**\
*Generates a faceted raster map from a multi-layer categorical SpatRaster, where each layer is one classification (e.g., model/experiment). For each layer, it computes user’s accuracy (UA), producer’s accuracy (PA), F1-score, and area of the target class inside and outside the provided polygons; all metrics are calculated by the spatial characteristics. Optionally overlays the polygons on the map and annotates facet strip labels with accuracy and/or area metrics. Designed to geospatial analysis when the reference data consists of polygons covering all target objects (roofs, mines, buildings, invasive species habitats with well-defined borders).*

**Usage**

```
spatial_accuracy(
  input_raster,
  polygons,
  target_class = "class_a",
  other_class = "class_b",
  label_type = c("accuracy", "scr", "both"),
  show_polygons = TRUE,
  polygon_color = "black",
  polygon_fill = "transparent",
  polygon_size = 0.5,
  polygon_alpha = 0.7,
  ncol_facet = 3,
  strip_text_size = 7
)
```

**Arguments**

> - input_raster (SpatRaster): Multi-layer binary categorical rasters; submap (i.e., faceted maps) names will be equal to file names
> - polygons (SpatVector): Reference polygons used to compute inside/outside metrics (inside: true positives, outside: false positives). Reprojected automatically to match the raster CRS if needed.
> - target_class (character): Name of the class in the raster category table to be treated as true positive/target class.
> - other_class (character): Name of the class in the raster category table to be treated as false positive/other class.
> - label_type (character): One of "accuracy", "scr", or "both". Controls which metrics are printed in facet strip labels; accuracy as UA/PA/F1 or SCR as Spatially Correct Ratio 
> - show_polygons (logical): If TRUE, overlays polygons on the map. Defaults to TRUE.
> - polygon_color (character): Polygon outline color. Defaults to "black".
> - polygon_fill (character): Polygon fill color (typically "transparent"). Defaults to "transparent".
> - polygon_size (numeric): Polygon outline width. Defaults to 0.5.
> - polygon_alpha (numeric): Polygon transparency (0 – 1). Defaults to 0.7.
> - ncol_facet (integer): Number of columns in facet layout. Defaults to 3.
> - strip_text_size (numeric): Facet strip text size. Defaults to 7.

**Value**

Returns a list with two elements:
 - plot: A ggplot object (facet map) of the input layers.
 - metrics: A data.frame with per-layer metrics and areas, with columns:
  UA, PA, F1, inside_m2, outside_m2, percentage_in_polygon, n_pixels_inside,
  n_pixels_outside, SCR, Layer.


**Notes**\
*The input raster layers must be categorical (factor). The function reads the category table to match the provided target_class to its internal code. If the CRS differs between polygons and raster, the polygons are reprojected to the raster CRS.*

### Function: calculate_area

**Description**\
*Computes area-based statistics for a single categorical classification raster relative to reference polygons. Specifically, it calculates the number of pixels and area of the target class inside and outside the polygons, the total polygon area, and the proportion of the target class within the polygons.*

**Usage**

```
calculate_area(
  raster_layer,
  polygons,
  target_class
)
```
**Arguments**

> - raster_layer (SpatRaster): Single-layer categorical raster (factor-coded) with a category table containing the target_class.
> - polygons (SpatVector): Reference polygons. Reprojected automatically to match the raster CRS if needed.
> - target_class (character): Name of the class in the raster category table to be treated as the positive/target class.

**Value**

A data.frame with the following columns:
  target_class, pixels_inside, pixels_outside,
  area_inside_m2, area_outside_m2,
  total_polygon_area_m2, percentage_in_polygon,
  pixel_size_m2, SCR

**Notes**\
*The raster must be categorical (factor) and contain a category table mapping values to class labels. Pixel areas are computed from the raster resolution.*

---

# Complete workflow example

```
source("spatial_accuracy_tool.R")

# Load the required libraries
library(terra)
library(ggplot2)
library(tidyr)
library(dplyr)



# --- LOAD RASTERS FOR RF ---

# Original image
o_rf <- rast("rf.tif")   

# Experiments
ext1_rf <- rast("ext1_rf.tif")
ext2_rf <- rast("ext2_rf.tif")
ext_12_rf <- rast("ext12_rf.tif")
aug1_rf <- rast("aug1_rf.tif")


# --- LOAD RASTERS FOR MARS ---

# Original image
o_mars <- rast("mars.tif")

# Experiments
ext1_mars <- rast("ext1_mars.tif")
ext2_mars <- rast("ext2_mars.tif")
ext_12_mars <- rast("ext12_mars.tif")
aug1_mars <- rast("aug1_mars.tif")


# --- LOAD RASTERS FOR SVM ---

# Original image
o_svm <- rast("svm.tif")

# Experiments
ext1_svm <- rast("ext1_svm.tif")
ext2_svm <- rast("ext2_svm.tif")
ext_12_svm <- rast("ext12_svm.tif")
aug1_svm <- rast("aug1_svm.tif")

#Load reference vector
ref <- vect("reference.shp")

raster <- c(o_rf, o_mars, o_svm, ext1_rf,
            ext1_mars, ext1_svm,
            ext2_rf, ext2_mars, ext2_svm,
            ext_12_rf, ext_12_mars, ext_12_svm,
            aug1_rf, aug1_mars, aug1_svm)


# Name loaded rasters
names(raster) <- c("o_rf", "o_mars", "o_svm", "ext1_rf",
                    "ext1_mars", "ext1_svm",
                   "ext2_rf", "ext2_mars", "ext2_svm",
                   "ext_12_rf", "ext_12_mars", "ext_12_svm",
                   "aug1_rf", "aug1_mars", "aug1_svm")


# Run the tool
results <- plot_classifications(
  input_raster = raster,
  target_class = "ASM",
  other_class = "Non.ASM",
  polygons = ref,
  label_type = "scr"
)


# Compute area-based statistics
calculate_area(raster_layer = o_rf,polygons = ref,target_class = "ASM")


# Print the results
print(results$plot)
print(results$metrics)


# Save the figure
ggsave(
  filename = "acc_area.jpg",
  plot = results$plot,   
  width = 8,             
  height = 12,           
  dpi = 300              
)


# Save the metrics
write.csv(results$metrics, "results.csv",row.names = FALSE)

```
