#!/usr/bin/env Rscript
# =============================================================================
# save_snapshot.R — Multi-Park Wait Time Collector
# =============================================================================
# Collects wait time snapshots from multiple parks via the Queue-Times API
# and appends them to a single CSV file. Schedule this to run every 30 minutes.
#
# Parks collected:
#   - Disney Magic Kingdom (ID 6)
#   - Universal Studios Orlando (ID 65)
#   - Islands of Adventure (ID 64)
#   - Epic Universe (ID 334)
#
# SETUP INSTRUCTIONS:
#
#   1. Place this file in your RStudio project folder (same folder as the .qmd)
#   2. Make sure you have tidyverse and jsonlite installed:
#        install.packages(c("tidyverse", "jsonlite"))
#   3. Test it once manually in RStudio:
#        source("save_snapshot.R")
#   4. Then automate it (see below).
#
# --- AUTOMATING ON MAC/LINUX (cron) ---
#   Open terminal and type: crontab -e
#   Add this line (adjust the path to YOUR project folder):
#     */30 * * * * cd /Users/YOURUSERNAME/path/to/project && /usr/local/bin/Rscript save_snapshot.R >> data/cron_log.txt 2>&1
#
#   To find your Rscript path, run in terminal: which Rscript
#
# --- AUTOMATING ON WINDOWS (Task Scheduler) ---
#   1. Open Task Scheduler (search for it in Start menu)
#   2. Click "Create Basic Task"
#   3. Name it "Wait Time Collector"
#   4. Trigger: Daily, then in Advanced set "Repeat task every 30 minutes"
#   5. Action: Start a program
#        Program: "C:\Program Files\R\R-4.x.x\bin\Rscript.exe"  (find your R version)
#        Arguments: save_snapshot.R
#        Start in: C:\Users\YOURUSERNAME\path\to\project
#   6. Click Finish
#
# Powered by Queue-Times.com (https://queue-times.com/)
# =============================================================================

library(tidyverse)
library(jsonlite)

# ---- Configuration ----
parks <- tibble(
  park_id   = c(6, 65, 64, 334),
  park_name = c("Magic Kingdom", "Universal Studios Orlando",
                "Islands of Adventure", "Epic Universe"),
  latitude  = c(28.4177, 28.4752, 28.4722, 28.4314),
  longitude = c(-81.5812, -81.4664, -81.4688, -81.5348)
)

output_dir  <- "data"
output_file <- file.path(output_dir, "wait_times_log.csv")

if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# ---- Fetch function ----
fetch_park <- function(park_id, park_name) {
  url <- paste0("https://queue-times.com/parks/", park_id, "/queue_times.json")

  tryCatch({
    raw <- fromJSON(url, flatten = TRUE)

    rides <- raw$lands |>
      select(land_name = name, rides) |>
      unnest(rides) |>
      rename(ride_id = id, ride_name = name)

    rides |>
      mutate(
        park_id        = park_id,
        park_name      = park_name,
        snapshot_time  = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        snapshot_tz    = Sys.timezone()
      ) |>
      select(park_id, park_name, land_name, ride_id, ride_name,
             is_open, wait_time, last_updated, snapshot_time, snapshot_tz)

  }, error = function(e) {
    message("  [SKIP] ", park_name, " — ", conditionMessage(e))
    return(NULL)
  })
}

# ---- Collect from all parks ----
cat("=== Wait Time Snapshot ===\n")
cat("Time:", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), "\n\n")

all_snapshots <- map2(parks$park_id, parks$park_name, function(id, nm) {
  cat("Fetching", nm, "(ID", id, ")... ")
  result <- fetch_park(id, nm)
  if (!is.null(result)) {
    cat(nrow(result), "rides\n")
  }
  result
}) |>
  compact() |>
  bind_rows()

# ---- Save to CSV ----
if (nrow(all_snapshots) > 0) {
  if (file.exists(output_file)) {
    write_csv(all_snapshots, output_file, append = TRUE)
  } else {
    write_csv(all_snapshots, output_file)
  }

  cat("\nSaved", nrow(all_snapshots), "rows to", output_file, "\n")

  # Print running totals
  if (file.exists(output_file)) {
    total <- nrow(read_csv(output_file, show_col_types = FALSE))
    cat("Total rows in dataset:", total, "\n")
  }
} else {
  cat("\nNo data collected — all parks failed. Check your internet connection.\n")
}
