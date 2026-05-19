from __future__ import annotations

import os
import platform
import json
import multiprocessing
import shutil
import subprocess
import tempfile
import threading
import traceback
import webbrowser
import wave
from datetime import datetime
from pathlib import Path
from time import perf_counter

import numpy as np
import sounddevice as sd
import uvicorn
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from faster_whisper import WhisperModel


BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = Path(os.getenv("WHISPER_DATA_DIR", str(BASE_DIR))).expanduser()
MODEL_DIR = Path(os.getenv("WHISPER_MODEL_DIR", str(DATA_DIR / "models"))).expanduser()
STATIC_DIR = BASE_DIR / "static"
TEMPLATES_DIR = BASE_DIR / "templates"
SETTINGS_PATH = Path(os.getenv("WHISPER_SETTINGS_PATH", str(DATA_DIR / "settings.json"))).expanduser()
DEFAULT_OUTPUT_DIR = Path(os.getenv("WHISPER_OUTPUT_DIR", str(DATA_DIR / "recordings"))).expanduser()

MODEL_SIZE = os.getenv("WHISPER_MODEL", "medium")
DEVICE = os.getenv("WHISPER_DEVICE", "cpu")
COMPUTE_TYPE = os.getenv("WHISPER_COMPUTE_TYPE", "float32")
MAX_UPLOAD_BYTES = int(os.getenv("WHISPER_MAX_UPLOAD_MB", "1024")) * 1024 * 1024
SYSTEM_SAMPLE_RATE = int(os.getenv("WHISPER_SYSTEM_SAMPLE_RATE", "48000"))
FALLBACK_LANGUAGE = "ru"
DEFAULT_LANGUAGE = os.getenv("WHISPER_LANGUAGE", "ru").strip().lower() or "ru"
SUPPORTED_LANGUAGES = {"auto", "ru", "en", "uk", "be"}


class ModelLoadError(RuntimeError):
    pass


def load_whisper_model() -> WhisperModel:
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    print(
        "Loading Whisper model "
        f"'{MODEL_SIZE}' on {DEVICE} with compute_type={COMPUTE_TYPE}..."
    )
    return WhisperModel(
        MODEL_SIZE,
        device=DEVICE,
        compute_type=COMPUTE_TYPE,
        download_root=str(MODEL_DIR),
    )


MODEL: WhisperModel | None = None
MODEL_LOCK = threading.Lock()
MODEL_READY = threading.Event()
MODEL_LOADING = False
MODEL_ERROR: str | None = None
MODEL_STARTED_AT: datetime | None = None
MODEL_FINISHED_AT: datetime | None = None


def ensure_data_dirs() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    DEFAULT_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


def model_status() -> dict[str, object]:
    with MODEL_LOCK:
        if MODEL is not None:
            state = "ready"
            message = "Модель загружена и готова."
        elif MODEL_LOADING:
            state = "loading"
            message = "Модель Whisper скачивается или загружается. Первый запуск может занять несколько минут."
        elif MODEL_ERROR:
            state = "error"
            message = MODEL_ERROR
        else:
            state = "idle"
            message = "Модель еще не загружалась."

        return {
            "state": state,
            "message": message,
            "model": MODEL_SIZE,
            "device": DEVICE,
            "compute_type": COMPUTE_TYPE,
            "model_dir": str(MODEL_DIR),
            "started_at": MODEL_STARTED_AT.isoformat() if MODEL_STARTED_AT else None,
            "finished_at": MODEL_FINISHED_AT.isoformat() if MODEL_FINISHED_AT else None,
        }


def start_model_preload() -> None:
    thread = threading.Thread(target=_preload_model, name="whisper-model-preload", daemon=True)
    thread.start()


def _preload_model() -> None:
    try:
        get_whisper_model()
    except Exception:
        traceback.print_exc()


def get_whisper_model() -> WhisperModel:
    global MODEL, MODEL_ERROR, MODEL_FINISHED_AT, MODEL_LOADING, MODEL_STARTED_AT

    with MODEL_LOCK:
        if MODEL is not None:
            return MODEL

        if MODEL_LOADING:
            wait_for_loading = True
        else:
            wait_for_loading = False
            MODEL_LOADING = True
            MODEL_ERROR = None
            MODEL_STARTED_AT = datetime.now()
            MODEL_FINISHED_AT = None
            MODEL_READY.clear()

    if wait_for_loading:
        MODEL_READY.wait()
        with MODEL_LOCK:
            if MODEL is not None:
                return MODEL
            raise ModelLoadError(MODEL_ERROR or "Модель Whisper не загрузилась.")

    try:
        loaded_model = load_whisper_model()
    except Exception as exc:
        error_message = (
            "Не получилось загрузить модель Whisper. "
            f"Путь модели: {MODEL_DIR}. Ошибка: {exc}"
        )
        with MODEL_LOCK:
            MODEL_ERROR = error_message
            MODEL_LOADING = False
            MODEL_FINISHED_AT = datetime.now()
            MODEL_READY.set()
        raise ModelLoadError(error_message) from exc

    with MODEL_LOCK:
        MODEL = loaded_model
        MODEL_LOADING = False
        MODEL_ERROR = None
        MODEL_FINISHED_AT = datetime.now()
        MODEL_READY.set()
        return MODEL


app = FastAPI(title="Record-Whisper")
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
SERVER: uvicorn.Server | None = None


@app.on_event("startup")
async def startup() -> None:
    ensure_data_dirs()
    start_model_preload()


def is_loopback_name(name: str) -> bool:
    lowered = name.lower()
    return any(
        marker in lowered
        for marker in (
            "blackhole",
            "loopback",
            "piezo",
            "soundflower",
            "zoom",
            "aggregate",
            "многовыход",
        )
    )


def input_devices() -> list[dict[str, object]]:
    devices = sd.query_devices()
    default_input = sd.default.device[0]
    result: list[dict[str, object]] = []

    for index, device in enumerate(devices):
        max_input_channels = int(device.get("max_input_channels") or 0)
        if max_input_channels <= 0:
            continue

        name = str(device.get("name") or f"Device {index}")
        result.append(
            {
                "id": index,
                "name": name,
                "channels": max_input_channels,
                "default": index == default_input,
                "loopback_hint": is_loopback_name(name),
            }
        )

    return result


def recommended_device_ids(devices: list[dict[str, object]]) -> dict[str, int | None]:
    incoming = next((device["id"] for device in devices if device["loopback_hint"]), None)
    microphone = next((device["id"] for device in devices if device["default"]), None)

    if microphone is None and devices:
        microphone = int(devices[0]["id"])

    return {
        "incoming_device": int(incoming) if incoming is not None else None,
        "microphone_device": int(microphone) if microphone is not None else None,
    }


def write_wav(path: Path, audio: np.ndarray, sample_rate: int) -> None:
    clipped = np.clip(audio, -1.0, 1.0)
    pcm = (clipped * 32767.0).astype(np.int16)

    with wave.open(str(path), "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(pcm.tobytes())


class SystemAudioRecorder:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.streams: list[sd.InputStream] = []
        self.buffers: dict[str, list[np.ndarray]] = {}
        self.labels: list[str] = []
        self.mode = ""
        self.started_at: datetime | None = None
        self.sample_rate = SYSTEM_SAMPLE_RATE
        self.levels: dict[str, float] = {}
        self.peak_levels: dict[str, float] = {}

    def start(self, mode: str, incoming_device: int | None, microphone_device: int | None) -> dict[str, object]:
        with self.lock:
            if self.streams:
                raise HTTPException(status_code=409, detail="Системная запись уже идет.")

            targets: list[tuple[str, int]] = []
            if mode == "all":
                targets = [
                    (f"device-{device['id']}", int(device["id"]))
                    for device in input_devices()
                ]
            if mode in ("mixed", "incoming"):
                if incoming_device is None:
                    raise HTTPException(status_code=400, detail="Выберите устройство для приходящего звука.")
                targets.append(("incoming", incoming_device))
            if mode in ("mixed", "microphone"):
                if microphone_device is None:
                    raise HTTPException(status_code=400, detail="Выберите микрофон.")
                targets.append(("microphone", microphone_device))

            if not targets:
                raise HTTPException(status_code=400, detail="Выберите режим записи.")

            self.buffers = {label: [] for label, _device in targets}
            self.levels = {label: 0.0 for label, _device in targets}
            self.peak_levels = {label: 0.0 for label, _device in targets}
            self.labels = [label for label, _device in targets]
            self.mode = mode
            self.started_at = datetime.now()

            try:
                for label, device_id in targets:
                    stream = sd.InputStream(
                        device=device_id,
                        channels=1,
                        samplerate=self.sample_rate,
                        dtype="float32",
                        blocksize=2048,
                        callback=self._callback(label),
                    )
                    stream.start()
                    self.streams.append(stream)
            except Exception as exc:
                self._close_locked()
                raise HTTPException(
                    status_code=500,
                    detail=(
                        "Не получилось начать системную запись. "
                        "Проверьте разрешение микрофона для Terminal/Python и выбранные устройства."
                    ),
                ) from exc

            return {
                "recording": True,
                "mode": self.mode,
                "labels": self.labels,
                "sample_rate": self.sample_rate,
            }

    def stop(self, save: bool) -> dict[str, object]:
        with self.lock:
            if not self.streams:
                raise HTTPException(status_code=409, detail="Системная запись не запущена.")

            buffers = {label: list(items) for label, items in self.buffers.items()}
            peak_levels = dict(self.peak_levels)
            mode = self.mode or "system"
            self._close_locked()

        temp_path: Path | None = None
        try:
            mixed_audio = self._mix_buffers(buffers)
            if mixed_audio.size == 0:
                raise HTTPException(status_code=400, detail="Запись пустая.")

            with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as temp_file:
                temp_path = Path(temp_file.name)

            write_wav(temp_path, mixed_audio, self.sample_rate)
            result = transcribe_file(temp_path)
            result["recording_levels"] = peak_levels
            if save:
                result["saved"] = save_artifacts(temp_path, f"system-{mode}.wav", result)
            return result
        except HTTPException:
            raise
        except ModelLoadError as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc
        except Exception as exc:
            raise HTTPException(
                status_code=500,
                detail="Не получилось обработать системную запись.",
            ) from exc
        finally:
            if temp_path:
                temp_path.unlink(missing_ok=True)

    def status(self) -> dict[str, object]:
        with self.lock:
            return {
                "recording": bool(self.streams),
                "mode": self.mode,
                "labels": self.labels,
                "started_at": self.started_at.isoformat() if self.started_at else None,
                "levels": dict(self.levels),
                "peak_levels": dict(self.peak_levels),
            }

    def _callback(self, label: str):
        def callback(indata, _frames, _time, _status) -> None:
            buffers = self.buffers.get(label)
            if buffers is not None:
                data = indata[:, 0].copy()
                buffers.append(data)
                level = float(np.sqrt(np.mean(np.square(data)))) if data.size else 0.0
                self.levels[label] = level
                self.peak_levels[label] = max(self.peak_levels.get(label, 0.0), level)

        return callback

    def _close_locked(self) -> None:
        for stream in self.streams:
            try:
                stream.stop()
            finally:
                stream.close()

        self.streams = []
        self.buffers = {}
        self.labels = []
        self.mode = ""
        self.started_at = None
        self.levels = {}
        self.peak_levels = {}

    @staticmethod
    def _mix_buffers(buffers: dict[str, list[np.ndarray]]) -> np.ndarray:
        tracks: list[np.ndarray] = []

        for parts in buffers.values():
            if not parts:
                continue
            tracks.append(np.concatenate(parts))

        if not tracks:
            return np.array([], dtype=np.float32)

        max_length = max(track.shape[0] for track in tracks)
        padded_tracks = []
        for track in tracks:
            if track.shape[0] < max_length:
                track = np.pad(track, (0, max_length - track.shape[0]))
            padded_tracks.append(track)

        mixed = np.mean(np.stack(padded_tracks, axis=0), axis=0)
        return mixed.astype(np.float32)


SYSTEM_RECORDER = SystemAudioRecorder()


def normalize_language(language: str | None) -> str:
    candidate = (language or DEFAULT_LANGUAGE).strip().lower()
    if candidate not in SUPPORTED_LANGUAGES:
        return FALLBACK_LANGUAGE
    return candidate


def load_settings() -> dict[str, str]:
    settings = {
        "output_dir": str(DEFAULT_OUTPUT_DIR),
        "language": normalize_language(DEFAULT_LANGUAGE),
    }

    if SETTINGS_PATH.exists():
        try:
            data = json.loads(SETTINGS_PATH.read_text(encoding="utf-8"))
            if data.get("output_dir"):
                settings["output_dir"] = str(data["output_dir"])
            if data.get("language"):
                settings["language"] = normalize_language(str(data["language"]))
        except Exception:
            pass

    return settings


def save_settings(settings: dict[str, str]) -> None:
    SETTINGS_PATH.parent.mkdir(parents=True, exist_ok=True)
    SETTINGS_PATH.write_text(
        json.dumps(settings, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def load_output_dir() -> Path:
    return Path(load_settings()["output_dir"]).expanduser()


def save_output_dir(output_dir: Path) -> None:
    settings = load_settings()
    settings["output_dir"] = str(output_dir)
    save_settings(settings)


def save_transcription_language(language: str) -> None:
    settings = load_settings()
    settings["language"] = normalize_language(language)
    save_settings(settings)


def load_transcription_language() -> str:
    return normalize_language(load_settings()["language"])


def ensure_output_dir(output_dir: Path) -> Path:
    output_dir = output_dir.expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    return output_dir


def safe_stem(filename: str | None) -> str:
    raw = Path(filename or "audio").stem.strip() or "audio"
    allowed = [char if char.isalnum() or char in ("-", "_") else "_" for char in raw]
    cleaned = "".join(allowed).strip("_")
    return cleaned[:48] or "audio"


def save_artifacts(source_path: Path, original_name: str | None, result: dict[str, object]) -> dict[str, str]:
    output_dir = ensure_output_dir(load_output_dir())
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    stem = f"{timestamp}-{safe_stem(original_name)}"
    suffix = source_path.suffix or ".audio"

    audio_path = output_dir / f"{stem}{suffix}"
    text_path = output_dir / f"{stem}.txt"

    shutil.copy2(source_path, audio_path)
    text_path.write_text(str(result["text"]).strip() + "\n", encoding="utf-8")

    return {
        "audio_path": str(audio_path),
        "text_path": str(text_path),
        "output_dir": str(output_dir),
    }


def suffix_for_upload(upload: UploadFile) -> str:
    suffix = Path(upload.filename or "").suffix.lower()
    if suffix and len(suffix) <= 12:
        return suffix

    content_type = upload.content_type or ""
    if "webm" in content_type:
        return ".webm"
    if "ogg" in content_type:
        return ".ogg"
    if "mp4" in content_type or "mpeg" in content_type:
        return ".mp4"
    if "wav" in content_type:
        return ".wav"
    return ".audio"


def transcribe_file(audio_path: Path) -> dict[str, object]:
    started_at = perf_counter()
    language_setting = load_transcription_language()
    transcribe_options: dict[str, object] = {
        "beam_size": 5,
        "best_of": 5,
        "temperature": 0.0,
        "vad_filter": True,
        "vad_parameters": {"min_silence_duration_ms": 500},
    }

    if language_setting != "auto":
        transcribe_options["language"] = language_setting

    segments, info = get_whisper_model().transcribe(
        str(audio_path),
        **transcribe_options,
    )

    parts: list[str] = []
    for segment in segments:
        text = segment.text.strip()
        if text:
            parts.append(text)

    elapsed = perf_counter() - started_at
    transcript = " ".join(parts).strip()
    language = info.language or "не определен"
    probability = info.language_probability or 0

    if not transcript:
        transcript = "Речь не найдена. Проверьте, что источник содержит голос."

    return {
        "text": transcript,
        "language": language,
        "language_setting": language_setting,
        "language_forced": language_setting != "auto",
        "language_probability": probability,
        "elapsed_seconds": round(elapsed, 1),
    }


@app.get("/", response_class=HTMLResponse)
async def index() -> str:
    return (TEMPLATES_DIR / "index.html").read_text(encoding="utf-8")


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/model-status")
async def get_model_status() -> dict[str, object]:
    return model_status()


@app.post("/model/retry")
async def retry_model_load() -> dict[str, object]:
    start_model_preload()
    return model_status()


@app.get("/config")
async def config() -> dict[str, str]:
    return {
        "model": MODEL_SIZE,
        "device": DEVICE,
        "compute_type": COMPUTE_TYPE,
        "output_dir": str(load_output_dir()),
        "language": load_transcription_language(),
        "model_state": str(model_status()["state"]),
    }


@app.get("/audio-devices")
async def audio_devices() -> dict[str, object]:
    devices = input_devices()
    return {
        "input_devices": devices,
        "recommended": recommended_device_ids(devices),
        "recording": SYSTEM_RECORDER.status(),
    }


@app.post("/system-recording/start")
async def start_system_recording(
    mode: str = Form(...),
    incoming_device: int | None = Form(None),
    microphone_device: int | None = Form(None),
) -> dict[str, object]:
    return await run_in_threadpool(
        SYSTEM_RECORDER.start,
        mode,
        incoming_device,
        microphone_device,
    )


@app.post("/system-recording/stop")
async def stop_system_recording(save: bool = Form(True)) -> dict[str, object]:
    return await run_in_threadpool(SYSTEM_RECORDER.stop, save)


@app.get("/system-recording/status")
async def system_recording_status() -> dict[str, object]:
    return SYSTEM_RECORDER.status()


@app.post("/shutdown")
async def shutdown() -> dict[str, str]:
    if SYSTEM_RECORDER.status()["recording"]:
        raise HTTPException(status_code=409, detail="Сначала остановите запись.")

    def stop_server() -> None:
        if SERVER:
            SERVER.should_exit = True

    timer = threading.Timer(0.2, stop_server)
    timer.daemon = True
    timer.start()
    return {"status": "shutting_down"}


@app.post("/settings")
async def update_settings(
    output_dir: str | None = Form(None),
    language: str | None = Form(None),
) -> dict[str, str]:
    if output_dir is None and language is None:
        raise HTTPException(status_code=400, detail="Нет настроек для сохранения.")

    if output_dir is not None:
        if not output_dir.strip():
            raise HTTPException(status_code=400, detail="Укажите папку для сохранения.")

        try:
            resolved_output_dir = ensure_output_dir(Path(output_dir))
        except Exception as exc:
            raise HTTPException(status_code=400, detail="Не получилось открыть эту папку.") from exc

        save_output_dir(resolved_output_dir)

    if language is not None:
        normalized_language = normalize_language(language)
        if normalized_language != language.strip().lower():
            raise HTTPException(status_code=400, detail="Такой язык распознавания не поддержан.")
        save_transcription_language(normalized_language)

    return {
        "output_dir": str(load_output_dir()),
        "language": load_transcription_language(),
    }


@app.post("/choose-output-folder")
async def choose_output_folder() -> dict[str, str]:
    if platform.system() != "Darwin":
        raise HTTPException(
            status_code=400,
            detail="Автовыбор папки сейчас сделан для macOS. Введите путь вручную.",
        )

    script = 'POSIX path of (choose folder with prompt "Куда сохранять записи Whisper?")'
    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            check=False,
            capture_output=True,
            text=True,
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail="Не получилось открыть выбор папки.") from exc

    if result.returncode != 0:
        raise HTTPException(status_code=400, detail="Выбор папки отменен.")

    selected_dir = ensure_output_dir(Path(result.stdout.strip()))
    save_output_dir(selected_dir)
    return {"output_dir": str(selected_dir)}


@app.post("/transcribe")
async def transcribe(upload: UploadFile = File(...), save: bool = Form(True)) -> dict[str, object]:
    content = await upload.read()
    if not content:
        raise HTTPException(status_code=400, detail="Аудиофайл пустой.")
    if len(content) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="Файл слишком большой.")

    suffix = suffix_for_upload(upload)
    temp_path: Path | None = None

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temp_file:
            temp_file.write(content)
            temp_path = Path(temp_file.name)

        result = await run_in_threadpool(transcribe_file, temp_path)
        if save:
            result["saved"] = await run_in_threadpool(save_artifacts, temp_path, upload.filename, result)
        return result
    except HTTPException:
        raise
    except ModelLoadError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=(
                "Не получилось распознать аудио. "
                "Проверьте формат файла или попробуйте другой источник."
            ),
        ) from exc
    finally:
        if temp_path:
            temp_path.unlink(missing_ok=True)


@app.post("/transcribe-path")
async def transcribe_path(path: str = Form(...), save: bool = Form(True)) -> dict[str, object]:
    audio_path = Path(path).expanduser()
    if not audio_path.is_file():
        raise HTTPException(status_code=400, detail="Файл не найден.")

    try:
        result = await run_in_threadpool(transcribe_file, audio_path)
        if save:
            result["saved"] = await run_in_threadpool(save_artifacts, audio_path, audio_path.name, result)
        return result
    except ModelLoadError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=(
                "Не получилось распознать аудио. "
                "Проверьте формат файла или попробуйте другой источник."
            ),
        ) from exc


def open_browser_later(url: str) -> None:
    def open_url() -> None:
        if platform.system() == "Darwin":
            chrome_check = subprocess.run(
                ["open", "-Ra", "Google Chrome"],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            if chrome_check.returncode == 0:
                subprocess.run(
                    ["open", "-a", "Google Chrome", url],
                    check=False,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                return

        webbrowser.open(url)

    timer = threading.Timer(1.0, open_url)
    timer.daemon = True
    timer.start()


if __name__ == "__main__":
    multiprocessing.freeze_support()

    port = int(os.getenv("PORT", "7860"))
    host = "127.0.0.1"
    url = f"http://{host}:{port}"

    if os.getenv("WHISPER_OPEN_BROWSER", "1") != "0":
        open_browser_later(url)

    config = uvicorn.Config(app, host=host, port=port)
    SERVER = uvicorn.Server(config)
    SERVER.run()
