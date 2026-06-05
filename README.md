<!-- 
Add a project state badge

See <https://github.com/BCDevExchange/Our-Project-Docs/blob/master/discussion/projectstates.md> 
If you have bcgovr installed and you use RStudio, click the 'Insert BCDevex Badge' Addin.
-->

text_scoring_r
============================

# Setting Up Ollama + Mistral on Windows

## 1. Install Ollama

1. Go to [ollama.com](https://ollama.com) and click **Download for Windows**
2. Run the installer — it installs Ollama and starts it automatically as a background service
3. Verify it's running by opening a browser and going to `http://localhost:11434` — you should see `Ollama is running`

---

## 2. Pull the Mistral model

Open **Command Prompt** or **PowerShell** and run:

```
ollama pull mistral
```

This downloads the model (~4GB). Only needed once.

---

## 3. Enable parallel requests

Ollama on Windows runs as a background app, not a system service. Set the environment variable through Windows Settings:

1. Open **Start** → search **"Edit the system environment variables"**
2. Click **Environment Variables...**
3. Under **User variables**, click **New**
4. Set:
   - Variable name: `OLLAMA_NUM_PARALLEL`
   - Variable value: `4`
5. Click OK
6. **Restart your computer** for it to take effect

Verify it's working by opening Command Prompt and running:
```
ollama serve
```
It should mention the parallel setting, or simply confirm it's already running.

---

## 4. Install R packages

In R:

```r
install.packages(c("glue", "jsonlite", "httr2", "furrr", "purrr", "dplyr"))
```

---

## 5. Verify everything works

In R:

```r
httr2::request("http://localhost:11434/api/generate") |>
  httr2::req_body_json(list(model = "mistral", prompt = "hello", stream = FALSE)) |>
  httr2::req_perform() |>
  httr2::resp_body_json() |>
  _$response
```

Should return a short text response. If it errors, Ollama isn't running — find the Ollama icon in the system tray (bottom-right of taskbar) and click **Start**.

---

## Notes

- Ollama runs quietly in the system tray — look for the icon if you need to start/stop it
- The Mistral model (~4GB) is stored locally; no data ever leaves your machine
- Minimum specs: 8GB RAM (16GB recommended for comfortable performance)

### License

```
Copyright 2026 Province of British Columbia

Licensed under the Apache License, Version 2.0 (the &quot;License&quot;);
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an &quot;AS IS&quot; BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and limitations under the License.
```
---
*This project was created using the [bcgovr](https://github.com/bcgov/bcgovr) package.* 
