library(glue)
library(jsonlite)
library(httr2)
library(furrr)
library(purrr)
library(dplyr)

# -------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------

OLLAMA_URL      <- "http://localhost:11434/api/generate"
OLLAMA_MODEL    <- "mistral"
N_WORKERS       <- 4      # match OLLAMA_NUM_PARALLEL
CHECKPOINT_FILE <- "scoring_checkpoint.rds"
CHECKPOINT_EVERY <- 50    # save to disk every N texts

# -------------------------------------------------------------------
# Scoring function
# -------------------------------------------------------------------

score_text <- function(text, attributes) {

  attr_list <- paste(attributes, collapse = "\n- ")

  prompt <- glue(
    "Score the following text on each attribute below using two values:

     'relevance': 0 to 1, where 0 = not mentioned/irrelevant, 1 = central to the text
     'valence':  -5 to +5, where -5 = very negative, 0 = neutral, +5 = very positive
                 (set to null if relevance = 0)

     Respond ONLY with a JSON object like:
     {{
       \"attribute1\": {{\"relevance\": 0.8, \"valence\": -3}},
       \"attribute2\": {{\"relevance\": 0.0, \"valence\": null}}
     }}
     Important: valence must be a plain integer with no + sign (e.g. 5 not +5).
     No explanation, no markdown, just the JSON.

     Attributes:
     - {attr_list}

     Text:
     {text}"
  )

  tryCatch({

    raw <- request(OLLAMA_URL) |>
      req_body_json(list(
        model   = OLLAMA_MODEL,
        prompt  = prompt,
        stream  = FALSE,
        options = list(num_predict = 2000)  # enough for any reasonable attribute list
      )) |>
      req_timeout(120) |>
      req_retry(max_tries = 3,
                backoff = ~ 5) |>
      req_perform() |>
      resp_body_json()

    # Strip any leading + before parsing
    cleaned <- gsub("+", "", raw$response, fixed = TRUE)

    fromJSON(cleaned)

  }, error = function(e) {
    warning(glue("Failed for text: {substr(text, 1, 50)}...\nError: {e$message}"))
    NULL
  })
}

# -------------------------------------------------------------------
# Flatten nested JSON result into a tidy tibble
# -------------------------------------------------------------------

flatten_scores <- function(scores, text) {
  if (is.null(scores)) {
    return(tibble(text = text, attribute = NA, relevance = NA_real_, valence = NA_real_))
  }

  tibble(
    text      = text,
    attribute = names(scores),
    relevance = map_dbl(scores, ~ .x[["relevance"]] %||% NA_real_),
    valence   = map_dbl(scores, ~ .x[["valence"]]   %||% NA_real_)
  )
}

# -------------------------------------------------------------------
# Checkpoint helpers
# -------------------------------------------------------------------

load_checkpoint <- function(checkpoint_file) {
  if (file.exists(checkpoint_file)) {
    message("Checkpoint found — resuming from previous run...")
    readRDS(checkpoint_file)
  } else {
    message("No checkpoint found — starting fresh...")
    tibble(text = character(), attribute = character(),
           relevance = numeric(), valence = numeric())
  }
}

save_checkpoint <- function(results, checkpoint_file) {
  tmp <- paste0(checkpoint_file, ".tmp")
  saveRDS(results, tmp)
  file.rename(tmp, checkpoint_file)  # atomic write — avoids corrupt file on crash
}

# -------------------------------------------------------------------
# Pipeline
# -------------------------------------------------------------------

run_pipeline <- function(texts, attributes,
                         workers          = N_WORKERS,
                         checkpoint_file  = CHECKPOINT_FILE,
                         checkpoint_every = CHECKPOINT_EVERY) {

  # Load any prior results
  completed <- load_checkpoint(checkpoint_file)

  # Identify which texts still need scoring
  done_texts    <- unique(completed$text)
  pending_texts <- texts[!texts %in% done_texts]

  n_done    <- length(done_texts)
  n_pending <- length(pending_texts)

  message(glue("{n_done} texts already scored, {n_pending} remaining..."))

  if (n_pending == 0) {
    message("All texts already scored — returning checkpoint results.")
    return(completed)
  }

  # Process in chunks for checkpointing
  chunks  <- split(pending_texts,
                   ceiling(seq_along(pending_texts) / checkpoint_every))
  results <- completed

  plan(multisession, workers = workers)
  on.exit(plan(sequential))

  for (i in seq_along(chunks)) {

    chunk <- chunks[[i]]
    message(glue("Processing chunk {i}/{length(chunks)} ({length(chunk)} texts)..."))

    chunk_scores <- future_map(
      chunk,
      \(t) score_text(t, attributes),
      .options = furrr_options(seed = TRUE),
      .progress = TRUE
    )

    chunk_results <- map2(chunk_scores, chunk, flatten_scores) |>
      list_rbind()

    results <- bind_rows(results, chunk_results)

    save_checkpoint(results, checkpoint_file)
    message(glue("Checkpoint saved — {nrow(filter(results, !is.na(attribute)))} texts scored so far."))
  }

  # Summarise failures
  n_failed <- results |> filter(is.na(attribute)) |> distinct(text) |> nrow()
  if (n_failed > 0) {
    message(glue("{n_failed} texts failed to parse — check rows where attribute is NA."))
  }

  results
}

# -------------------------------------------------------------------
# Example usage
# -------------------------------------------------------------------

attributes <- c("job satisfaction", "workload", "management quality")

texts <- c(
  "The team is great but we're completely overwhelmed and never hear anything useful from leadership.",
  "Honestly couldn't be happier — manageable hours and my manager is fantastic.",
  "The weather has been lovely this week."
)

results <- run_pipeline(texts, attributes)

# Inspect failures
failures <- results |> filter(is.na(attribute))

# Analysis-ready: filter to relevant scores only
scored <- results |>
  filter(!is.na(attribute), relevance >= 0.3) |>
  arrange(attribute, desc(relevance))

print(scored)

# Once happy, clean up checkpoint
# file.remove(CHECKPOINT_FILE)
