const fileInput = document.querySelector("#fileInput");
const fileButton = document.querySelector("#fileButton");
const copyButton = document.querySelector("#copyButton");
const shutdownButton = document.querySelector("#shutdownButton");
const refreshDevicesButton = document.querySelector("#refreshDevicesButton");
const languageSelect = document.querySelector("#languageSelect");
const outputDirInput = document.querySelector("#outputDirInput");
const chooseFolderButton = document.querySelector("#chooseFolderButton");
const saveFilesCheckbox = document.querySelector("#saveFilesCheckbox");
const systemModeSelect = document.querySelector("#systemModeSelect");
const incomingSelect = document.querySelector("#incomingSelect");
const systemMicSelect = document.querySelector("#systemMicSelect");
const systemStartButton = document.querySelector("#systemStartButton");
const systemStopButton = document.querySelector("#systemStopButton");
const statusLine = document.querySelector("#status");
const routeHint = document.querySelector("#routeHint");
const output = document.querySelector("#output");
const resultMeta = document.querySelector("#resultMeta");
const modelInfo = document.querySelector("#modelInfo");
const preview = document.querySelector("#preview");

let isSystemRecording = false;
let statusTimer = null;
let modelStatusTimer = null;
let modelState = "idle";
let inputDevices = [];
const languageLabels = {
  auto: "авто",
  ru: "русский",
  en: "английский",
  uk: "украинский",
  be: "белорусский",
};

function setStatus(text, state = "idle") {
  statusLine.textContent = text;
  statusLine.dataset.state = state;
}

function setModelInfo(data) {
  modelState = data.state || "idle";
  modelInfo.dataset.state = modelState;

  const base = `${data.model || "medium"} · ${data.device || "cpu"} · ${data.compute_type || "float32"}`;
  if (modelState === "ready") {
    modelInfo.textContent = `${base} · готова`;
    return;
  }
  if (modelState === "loading") {
    modelInfo.textContent = `${base} · скачивается/загружается`;
    return;
  }
  if (modelState === "error") {
    modelInfo.textContent = `${base} · ошибка загрузки`;
    setStatus(data.message || "Модель Whisper не загрузилась.", "error");
    return;
  }

  modelInfo.textContent = `${base} · ожидает загрузки`;
}

async function refreshModelStatus() {
  try {
    const response = await fetch("/model-status");
    const data = await jsonOrEmpty(response);
    if (!response.ok) {
      throw new Error(data.detail || "Не получилось получить статус модели.");
    }
    setModelInfo(data);
  } catch {
    modelInfo.dataset.state = "error";
    modelInfo.textContent = "Статус модели недоступен";
  }
}

function startModelStatusPolling() {
  refreshModelStatus();
  if (modelStatusTimer) {
    window.clearInterval(modelStatusTimer);
  }
  modelStatusTimer = window.setInterval(refreshModelStatus, 1000);
}

function transcriptionStatusText(defaultText) {
  if (modelState === "ready") {
    return defaultText;
  }
  if (modelState === "error") {
    return "Повторяю загрузку модели и распознаю аудио";
  }
  return "Готовлю модель Whisper: скачивание или загрузка";
}

function percentLevel(value) {
  const normalized = Math.min(100, Math.round((Number(value) || 0) * 350));
  return `${normalized}%`;
}

function formatLevels(levels) {
  if (!levels || Object.keys(levels).length === 0) {
    return "";
  }

  return Object.entries(levels)
    .map(([label, value]) => `${labelName(label)} ${percentLevel(value)}`)
    .join(" · ");
}

function languageLabel(code) {
  return languageLabels[code] || code || "?";
}

function labelName(label) {
  if (label === "incoming") {
    return "приходящий";
  }
  if (label === "microphone") {
    return "микрофон";
  }
  return label;
}

function startStatusPolling() {
  stopStatusPolling();
  statusTimer = window.setInterval(async () => {
    try {
      const response = await fetch("/system-recording/status");
      const data = await jsonOrEmpty(response);
      if (!response.ok || !data.recording) {
        return;
      }

      const levels = formatLevels(data.levels);
      if (levels) {
        setStatus(`Идет запись: ${labelForMode(data.mode)} · ${levels}`, "recording");
      }
    } catch {
      // Best-effort display only.
    }
  }, 700);
}

function stopStatusPolling() {
  if (statusTimer) {
    window.clearInterval(statusTimer);
    statusTimer = null;
  }
}

function setControls(mode) {
  const recording = mode === "recording";
  const transcribing = mode === "transcribing";
  const disabled = recording || transcribing;

  fileButton.setAttribute("aria-disabled", disabled ? "true" : "false");
  systemStartButton.disabled = disabled;
  refreshDevicesButton.disabled = disabled;
  languageSelect.disabled = disabled;
  outputDirInput.disabled = disabled;
  chooseFolderButton.disabled = disabled;
  saveFilesCheckbox.disabled = disabled;
  systemModeSelect.disabled = disabled;
  incomingSelect.disabled = disabled || ["microphone", "all"].includes(systemModeSelect.value);
  systemMicSelect.disabled = disabled || ["incoming", "all"].includes(systemModeSelect.value);
  systemStopButton.disabled = !recording;
}

function showResult(data) {
  output.value = data.text || "";
  const probability = Math.round((data.language_probability || 0) * 100);
  const detectedLanguage = data.language || "?";
  const languageText = data.language_forced
    ? `${languageLabel(data.language_setting || detectedLanguage)}, задан вручную`
    : `${languageLabel(detectedLanguage)} (${detectedLanguage}), ${probability}%`;
  resultMeta.textContent = `${languageText}, ${data.elapsed_seconds || 0} сек.`;

  const levelWarning = lowIncomingWarning(data.recording_levels);

  if (levelWarning) {
    setStatus(levelWarning, "error");
  } else if (data.saved?.output_dir) {
    outputDirInput.value = data.saved.output_dir;
    setStatus(`Сохранено: ${data.saved.output_dir}`, "done");
  } else {
    setStatus("Готово", "done");
  }
}

function lowIncomingWarning(levels) {
  const mode = systemModeSelect.value;
  if (!levels || !["mixed", "incoming", "all"].includes(mode)) {
    return "";
  }

  const incomingLevel = levels.incoming;
  if (incomingLevel !== undefined && incomingLevel < 0.003) {
    return "Приходящий звук почти нулевой: Chrome/Mac не выводит звук в BlackHole.";
  }

  if (mode === "all") {
    const hasLoopbackSignal = Object.entries(levels)
      .filter(([label]) => label.startsWith("device-"))
      .some(([_label, value]) => Number(value) >= 0.003);
    if (!hasLoopbackSignal) {
      return "Все входы почти пустые: проверьте, что звук Mac направлен в BlackHole.";
    }
  }

  return "";
}

async function jsonOrEmpty(response) {
  try {
    return await response.json();
  } catch {
    return {};
  }
}

async function saveOutputDir(showStatus = true) {
  const outputDir = outputDirInput.value.trim();
  if (!outputDir) {
    if (showStatus) {
      setStatus("Укажите папку для сохранения.", "error");
    }
    return false;
  }

  const formData = new FormData();
  formData.append("output_dir", outputDir);

  try {
    const response = await fetch("/settings", {
      method: "POST",
      body: formData,
    });
    const data = await jsonOrEmpty(response);

    if (!response.ok) {
      throw new Error(data.detail || "Не получилось сохранить папку.");
    }

    outputDirInput.value = data.output_dir;
    if (showStatus) {
      setStatus("Папка сохранения обновлена.", "done");
    }
    return true;
  } catch (error) {
    if (showStatus) {
      setStatus(error.message || "Не получилось сохранить папку.", "error");
    }
    return false;
  }
}

async function saveLanguage(showStatus = true) {
  const formData = new FormData();
  formData.append("language", languageSelect.value || "ru");

  try {
    const response = await fetch("/settings", {
      method: "POST",
      body: formData,
    });
    const data = await jsonOrEmpty(response);

    if (!response.ok) {
      throw new Error(data.detail || "Не получилось сохранить язык.");
    }

    languageSelect.value = data.language || "ru";
    if (showStatus) {
      setStatus(`Язык распознавания: ${languageLabel(languageSelect.value)}.`, "done");
    }
    return true;
  } catch (error) {
    if (showStatus) {
      setStatus(error.message || "Не получилось сохранить язык.", "error");
    }
    return false;
  }
}

async function chooseOutputFolder() {
  setControls("transcribing");
  setStatus("Открываю выбор папки", "busy");

  try {
    const response = await fetch("/choose-output-folder", { method: "POST" });
    const data = await jsonOrEmpty(response);

    if (!response.ok) {
      throw new Error(data.detail || "Папка не выбрана.");
    }

    outputDirInput.value = data.output_dir;
    setStatus("Папка сохранения обновлена.", "done");
  } catch (error) {
    setStatus(error.message || "Папка не выбрана.", "error");
  } finally {
    setControls(isSystemRecording ? "recording" : "idle");
  }
}

async function transcribeFile(file, fallbackName = "recording.wav") {
  const languageSaved = await saveLanguage(false);
  if (!languageSaved) {
    return;
  }

  if (saveFilesCheckbox.checked) {
    const saved = await saveOutputDir(false);
    if (!saved) {
      setStatus("Папка записи недоступна. Выберите другую папку.", "error");
      return;
    }
  }

  const formData = new FormData();
  formData.append("upload", file, file.name || fallbackName);
  formData.append("save", saveFilesCheckbox.checked ? "true" : "false");

  setControls("transcribing");
  setStatus(transcriptionStatusText("Распознаю аудио"), "busy");

  try {
    const response = await fetch("/transcribe", {
      method: "POST",
      body: formData,
    });
    const data = await jsonOrEmpty(response);

    if (!response.ok) {
      throw new Error(data.detail || "Ошибка распознавания.");
    }

    showResult(data);
  } catch (error) {
    setStatus(error.message || "Не получилось распознать аудио", "error");
  } finally {
    setControls(isSystemRecording ? "recording" : "idle");
  }
}

async function transcribeLocalPath(path, displayName = "аудиофайл") {
  const languageSaved = await saveLanguage(false);
  if (!languageSaved) {
    return;
  }

  if (saveFilesCheckbox.checked) {
    const saved = await saveOutputDir(false);
    if (!saved) {
      setStatus("Папка записи недоступна. Выберите другую папку.", "error");
      return;
    }
  }

  const formData = new FormData();
  formData.append("path", path);
  formData.append("save", saveFilesCheckbox.checked ? "true" : "false");

  preview.hidden = true;
  setControls("transcribing");
  setStatus(transcriptionStatusText(`Распознаю файл: ${displayName}`), "busy");

  try {
    const response = await fetch("/transcribe-path", {
      method: "POST",
      body: formData,
    });
    const data = await jsonOrEmpty(response);

    if (!response.ok) {
      throw new Error(data.detail || "Ошибка распознавания.");
    }

    showResult(data);
  } catch (error) {
    setStatus(error.message || "Не получилось распознать аудио", "error");
  } finally {
    setControls(isSystemRecording ? "recording" : "idle");
  }
}

function deviceLabel(device, kind) {
  if (kind === "incoming") {
    if (device.loopback_hint) {
      return `${device.name} (виртуальный вход для системного звука)`;
    }
    return `${device.name} (микрофон/вход, не звук наушников)`;
  }

  const suffix = [
    device.default ? "по умолчанию" : "",
    device.loopback_hint ? "виртуальный" : "",
  ].filter(Boolean).join(", ");
  return suffix ? `${device.name} (${suffix})` : device.name;
}

function populateSelect(select, devices, selectedId, emptyLabel, kind) {
  select.replaceChildren();

  if (!devices.length) {
    const option = new Option(emptyLabel, "");
    option.disabled = true;
    select.add(option);
    return;
  }

  devices.forEach((device) => {
    select.add(new Option(deviceLabel(device, kind), String(device.id)));
  });

  if (selectedId !== null && selectedId !== undefined) {
    select.value = String(selectedId);
  }
}

function selectedIncomingDevice() {
  return inputDevices.find((device) => String(device.id) === incomingSelect.value);
}

function updateRouteHint() {
  const mode = systemModeSelect.value;
  if (!["mixed", "incoming"].includes(mode)) {
    routeHint.textContent = "";
    routeHint.dataset.state = "idle";
    return;
  }

  const device = selectedIncomingDevice();
  if (!device) {
    routeHint.textContent = "Выберите виртуальный вход вроде BlackHole 2ch.";
    routeHint.dataset.state = "warn";
    return;
  }

  if (!device.loopback_hint) {
    routeHint.textContent = "Это обычный вход/микрофон. Звук, который играет в наушниках, macOS отсюда не отдаст.";
    routeHint.dataset.state = "warn";
    return;
  }

  routeHint.textContent = "Для записи браузера системный выход macOS должен идти в Multi-Output: BlackHole + наушники.";
  routeHint.dataset.state = "ok";
}

async function loadAudioDevices(showStatus = false) {
  try {
    const response = await fetch("/audio-devices");
    const data = await jsonOrEmpty(response);

    if (!response.ok) {
      throw new Error(data.detail || "Не получилось получить устройства.");
    }

    inputDevices = data.input_devices || [];
    const incomingDevices = [...inputDevices].sort((a, b) => Number(b.loopback_hint) - Number(a.loopback_hint));
    const micDevices = [...inputDevices].sort((a, b) => Number(b.default) - Number(a.default));

    populateSelect(
      incomingSelect,
      incomingDevices,
      data.recommended?.incoming_device,
      "Входящий звук не найден",
      "incoming",
    );
    populateSelect(
      systemMicSelect,
      micDevices,
      data.recommended?.microphone_device,
      "Микрофон не найден",
      "microphone",
    );

    isSystemRecording = Boolean(data.recording?.recording);
    setControls(isSystemRecording ? "recording" : "idle");
    updateRouteHint();

    if (showStatus) {
      setStatus("Список устройств обновлен.", "done");
    }
  } catch (error) {
    setStatus(error.message || "Не получилось получить устройства.", "error");
  }
}

async function startSystemRecording() {
  const languageSaved = await saveLanguage(false);
  if (!languageSaved) {
    return;
  }

  if (saveFilesCheckbox.checked) {
    const saved = await saveOutputDir(false);
    if (!saved) {
      setStatus("Папка записи недоступна. Выберите другую папку.", "error");
      return;
    }
  }

  const mode = systemModeSelect.value;
  const formData = new FormData();
  formData.append("mode", mode);

  if (mode !== "microphone" && incomingSelect.value) {
    formData.append("incoming_device", incomingSelect.value);
  }
  if (mode !== "incoming" && mode !== "all" && systemMicSelect.value) {
    formData.append("microphone_device", systemMicSelect.value);
  }

  setControls("transcribing");
  setStatus("Запускаю системную запись", "busy");

  try {
    const response = await fetch("/system-recording/start", {
      method: "POST",
      body: formData,
    });
    const data = await jsonOrEmpty(response);

    if (!response.ok) {
      throw new Error(data.detail || "Не получилось начать запись.");
    }

    isSystemRecording = true;
    setControls("recording");
    setStatus(`Идет системная запись: ${labelForMode(mode)}`, "recording");
    startStatusPolling();
  } catch (error) {
    isSystemRecording = false;
    setControls("idle");
    setStatus(error.message || "Не получилось начать запись.", "error");
  }
}

async function stopSystemRecording() {
  await saveLanguage(false);

  const formData = new FormData();
  formData.append("save", saveFilesCheckbox.checked ? "true" : "false");

  setControls("transcribing");
  setStatus(transcriptionStatusText("Останавливаю и распознаю"), "busy");
  stopStatusPolling();

  try {
    const response = await fetch("/system-recording/stop", {
      method: "POST",
      body: formData,
    });
    const data = await jsonOrEmpty(response);

    if (!response.ok) {
      throw new Error(data.detail || "Не получилось остановить запись.");
    }

    isSystemRecording = false;
    showResult(data);
  } catch (error) {
    isSystemRecording = false;
    setStatus(error.message || "Не получилось обработать запись.", "error");
  } finally {
    setControls("idle");
  }
}

function labelForMode(mode) {
  if (mode === "incoming") {
    return "только приходящий";
  }
  if (mode === "microphone") {
    return "только микрофон";
  }
  if (mode === "all") {
    return "все входы";
  }
  return "приходящий + микрофон";
}

async function loadConfig() {
  try {
    const response = await fetch("/config");
    const config = await jsonOrEmpty(response);
    setModelInfo({
      state: config.model_state || "idle",
      model: config.model,
      device: config.device,
      compute_type: config.compute_type,
    });
    outputDirInput.value = config.output_dir || "";
    languageSelect.value = config.language || "ru";
  } catch {
    modelInfo.dataset.state = "error";
    modelInfo.textContent = "Конфиг недоступен";
  }
}

window.recordWhisperSelectedFile = (path, displayName) => {
  if (!path) {
    setStatus("Выбор файла отменен.", "idle");
    return;
  }
  transcribeLocalPath(path, displayName || "аудиофайл");
};

fileButton.addEventListener("click", (event) => {
  const bridge = window.webkit?.messageHandlers?.recordWhisper;
  if (!bridge || fileButton.getAttribute("aria-disabled") === "true") {
    return;
  }

  event.preventDefault();
  event.stopPropagation();
  bridge.postMessage({ type: "selectAudioFile" });
});

fileInput.addEventListener("change", async () => {
  if (fileButton.getAttribute("aria-disabled") === "true") {
    fileInput.value = "";
    return;
  }
  const file = fileInput.files?.[0];
  if (!file) {
    return;
  }
  preview.src = URL.createObjectURL(file);
  preview.hidden = false;
  await transcribeFile(file);
  fileInput.value = "";
});

systemModeSelect.addEventListener("change", () => {
  setControls(isSystemRecording ? "recording" : "idle");
  updateRouteHint();
});
incomingSelect.addEventListener("change", updateRouteHint);
refreshDevicesButton.addEventListener("click", () => loadAudioDevices(true));
chooseFolderButton.addEventListener("click", chooseOutputFolder);
outputDirInput.addEventListener("change", () => saveOutputDir(true));
languageSelect.addEventListener("change", () => saveLanguage(true));
systemStartButton.addEventListener("click", startSystemRecording);
systemStopButton.addEventListener("click", stopSystemRecording);

copyButton.addEventListener("click", async () => {
  if (!output.value.trim()) {
    setStatus("Нет текста для копирования.", "idle");
    return;
  }

  try {
    await navigator.clipboard.writeText(output.value);
    setStatus("Текст скопирован.", "done");
  } catch {
    setStatus("Не получилось скопировать текст.", "error");
  }
});

shutdownButton.addEventListener("click", async () => {
  if (isSystemRecording) {
    setStatus("Сначала остановите запись.", "error");
    return;
  }

  shutdownButton.disabled = true;
  setControls("transcribing");
  setStatus("Выключаю сервер", "busy");

  try {
    const response = await fetch("/shutdown", { method: "POST" });
    const data = await jsonOrEmpty(response);

    if (!response.ok) {
      throw new Error(data.detail || "Не получилось выключить сервер.");
    }

    setStatus("Сервер выключается. Это окно можно закрыть.", "done");
  } catch (error) {
    shutdownButton.disabled = false;
    setControls("idle");
    setStatus(error.message || "Не получилось выключить сервер.", "error");
  }
});

setControls("idle");
loadConfig();
startModelStatusPolling();
loadAudioDevices();
