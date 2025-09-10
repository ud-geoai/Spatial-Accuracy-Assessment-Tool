library(terra)
library(dplyr)
library(ggplot2)
library(tidyr)
library(sf)

spatial_accuracy <- function(input_raster, 
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
                                     ) {
  
  if (!inherits(input_raster, "SpatRaster")) {
    stop("The input raster must be a SpatRaster object")
  }
  if (!inherits(polygons, "SpatVector")) {
    stop("polygons must be a SpatVector object")
  }
  
  label_type <- match.arg(label_type)
  
  
  validate_predictions <- function(polygons, raster_layer, target_class = target_class) {
    if (!same.crs(polygons, raster_layer)) {
      polygons <- project(polygons, crs(raster_layer))
    }
    if (!is.factor(raster_layer)) stop("Raster must be categorical (factor).")
    
    cat_levels <- cats(raster_layer)[[1]]
    if (!target_class %in% cat_levels$class) {
      stop(sprintf("Target class '%s' not found. Classes: %s",
                   target_class, paste(unique(cat_levels$class), collapse = ", ")))
    }
    target_code <- cat_levels$value[cat_levels$class == target_class]
    if (length(target_code) != 1) stop("Target class maps to multiple raster codes.")
    
    mask_inside  <- mask(raster_layer, polygons)
    mask_outside <- mask(raster_layer, polygons, inverse = TRUE)
    
    values_inside <- as.vector(values(mask_inside))
    values_outside <- as.vector(values(mask_outside))
    
    tp <- sum(values_inside  == target_code, na.rm = TRUE)
    fn <- sum(values_inside  != target_code & !is.na(values_inside),  na.rm = TRUE)
    fp <- sum(values_outside == target_code, na.rm = TRUE)
    
    UA <- ifelse((tp + fp) > 0, tp / (tp + fp), NA_real_)
    PA <- ifelse((tp + fn) > 0, tp / (tp + fn), NA_real_)
    F1 <- ifelse((UA + PA) > 0, 2 * UA * PA / (UA + PA), NA_real_)
    
    pixel_area_m2 <- prod(res(raster_layer))
    
    n_pixels_inside <- sum(values_inside == target_code, na.rm = TRUE)
    area_inside_m2 <- n_pixels_inside * pixel_area_m2

    n_pixels_outside <- sum(values_outside == target_code, na.rm = TRUE)
    area_outside_m2 <- n_pixels_outside * pixel_area_m2

    total_polygon_area_m2 <- sum(expanse(polygons, unit = "m"))

    percentage_in_polygon <- ifelse(total_polygon_area_m2 > 0, 
                                        (area_inside_m2 / total_polygon_area_m2) * 100, 
                                        0)
    
    scr <- area_inside_m2/(area_inside_m2 + area_outside_m2)
    
    
    data.frame(
      UA = UA, 
      PA = PA, 
      F1 = F1, 
      inside_m2 = area_inside_m2,
      outside_m2 = area_outside_m2,
      percentage_in_polygon = percentage_in_polygon,
      n_pixels_inside = n_pixels_inside,
      n_pixels_outside = n_pixels_outside,
      SCR = scr,
      Layer = names(raster_layer)
    )
  }
  
  
  layer_order <- names(input_raster)
  metrics_list <- lapply(layer_order, function(nm) {
    validate_predictions(polygons, input_raster[[nm]], target_class)
  })
  metrics_df <- do.call(rbind, metrics_list)
  metrics_df$Layer <- factor(metrics_df$Layer, levels = layer_order)
  
  lab_map <- metrics_df %>%
    dplyr::mutate(
      label = case_when(
        label_type == "accuracy" ~ sprintf("%s\nUA=%.1f%% | PA=%.1f%% | F1=%.1f%%",
                                           Layer, UA*100, PA*100, F1*100),
        label_type == "scr" ~ sprintf("%s\nSCR=%.2f",
                                       Layer, SCR),
        label_type == "both" ~ sprintf("%s\nF1=%.1f%% | SCR=%.2f",
                                       Layer, F1*100, SCR),
        TRUE ~ as.character(Layer)
      )
    ) %>%
    dplyr::select(Layer, label)
  
  
  input_long <- as.data.frame(input_raster, xy = TRUE)
  input_long <- tidyr::pivot_longer(
    input_long,
    cols = all_of(layer_order),
    names_to = "Layer",
    values_to = "Class"
  )
  input_long$Layer <- factor(input_long$Layer, levels = layer_order)
  
  input_long <- left_join(input_long, lab_map, by = "Layer")
  label_levels <- lab_map$label[match(layer_order, lab_map$Layer)]
  input_long$label <- factor(input_long$label, levels = label_levels)
  
  input_long$Class <- as.factor(input_long$Class)
  
  
  
  polygon_df <- NULL
  if (show_polygons) {
    if (!same.crs(polygons, input_raster)) {
      polygons <- project(polygons, crs(input_raster))
    }
    
    polygon_sf <- sf::st_as_sf(polygons)
    polygon_df <- polygon_sf
  }
  
  
  
  fill_colors = setNames(
    c("red", "aliceblue"),
    c(target_class, other_class)
  )
  p <- ggplot(input_long, aes(x = x, y = y, fill = Class)) +
    geom_raster() +
    facet_wrap(~ label, ncol = ncol_facet) +
    coord_equal() +
    theme_minimal() +
    scale_fill_manual(values = fill_colors) +
    theme(
      axis.text.x  = element_text(angle = 45, hjust = 1),
      legend.position = "bottom",
      strip.text = element_text(size = strip_text_size)
    ) +
    xlab("") + ylab("")
  
  
  if (show_polygons && !is.null(polygon_df)) {
    p <- p + geom_sf(data = polygon_df, 
                     color = polygon_color,
                     fill = polygon_fill,
                     size = polygon_size,
                     alpha = polygon_alpha,
                     inherit.aes = FALSE)
  }
  
  return(list(plot = p, metrics = metrics_df))
}


calculate_area <- function(raster_layer, polygons, target_class) {
  
  if (!inherits(raster_layer, "SpatRaster")) {
    stop("raster_layer must be a SpatRaster object")
  }
  if (!inherits(polygons, "SpatVector")) {
    stop("polygons must be a SpatVector object")
  }
  
  if (!same.crs(polygons, raster_layer)) {
    polygons <- project(polygons, crs(raster_layer))
  }
  
  if (!is.factor(raster_layer)) {
    stop("Raster must be categorical (factor).")
  }
  
  cat_levels <- cats(raster_layer)[[1]]
  if (!target_class %in% cat_levels$class) {
    stop(sprintf("Target class '%s' not found. Available classes: %s",
                 target_class, paste(unique(cat_levels$class), collapse = ", ")))
  }
  
  target_code <- cat_levels$value[cat_levels$class == target_class]
  
  masked_inside <- mask(raster_layer, polygons)
  masked_outside <- mask(raster_layer, polygons, inverse = TRUE)
  
  values_inside <- as.vector(values(masked_inside))
  values_outside <- as.vector(values(masked_outside))
  
  pixel_area_m2 <- prod(res(raster_layer))
  
  n_pixels_inside <- sum(values_inside == target_code, na.rm = TRUE)
  area_inside_m2 <- n_pixels_inside * pixel_area_m2

  n_pixels_outside <- sum(values_outside == target_code, na.rm = TRUE)
  area_outside_m2 <- n_pixels_outside * pixel_area_m2

  total_polygon_area_m2 <- sum(expanse(polygons, unit = "m"))

  percentage_in_polygon <- ifelse(total_polygon_area_m2 > 0, 
                                      (area_inside_m2 / total_polygon_area_m2) * 100, 
                                      0)
  
  scr <- area_inside_m2/(area_inside_m2 + area_outside_m2)
  
  
  return(data.frame(
    target_class = target_class,
    pixels_inside = n_pixels_inside,
    pixels_outside = n_pixels_outside,
    area_inside_m2 = area_inside_m2,
    area_outside_m2 = area_outside_m2,
    total_polygon_area_m2 = total_polygon_area_m2,
    percentage_in_polygon = percentage_in_polygon,
    pixel_size_m2 = pixel_area_m2,
    SCR = scr
  ))
}
