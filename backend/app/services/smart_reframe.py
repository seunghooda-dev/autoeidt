from __future__ import annotations

import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


@dataclass(frozen=True)
class FocusSample:
    x: float
    y: float
    weight: float


def _weighted_median(values: Iterable[tuple[float, float]], fallback: float) -> float:
    ordered = sorted(
        (float(value), max(0.0, float(weight)))
        for value, weight in values
        if math.isfinite(float(value)) and math.isfinite(float(weight))
    )
    total = sum(weight for _, weight in ordered)
    if not ordered or total <= 0:
        return fallback
    cursor = 0.0
    for value, weight in ordered:
        cursor += weight
        if cursor >= total / 2:
            return value
    return ordered[-1][0]


def _sample_times(start: float, end: float, max_samples: int) -> list[float]:
    duration = max(0.0, end - start)
    if duration <= 0:
        return []
    count = max(1, min(max_samples, int(math.ceil(duration / 1.5))))
    if count == 1:
        return [(start + end) / 2]
    padding = min(0.35, duration * 0.08)
    first = start + padding
    last = end - padding
    if last <= first:
        return [(start + end) / 2]
    step = (last - first) / (count - 1)
    return [first + step * index for index in range(count)]


def _choose_face(
    faces: Iterable[tuple[int, int, int, int]],
    frame_width: int,
    frame_height: int,
    previous_x: float | None,
) -> FocusSample | None:
    best: FocusSample | None = None
    best_score = -1.0
    frame_area = max(1.0, float(frame_width * frame_height))
    for left, top, width, height in faces:
        if width <= 0 or height <= 0:
            continue
        x = (left + width / 2) / frame_width
        y = (top + height / 2) / frame_height
        area_ratio = (width * height) / frame_area
        center_distance = abs(x - 0.5)
        continuity = 0.0
        if previous_x is not None:
            continuity = max(0.0, 1.0 - abs(x - previous_x) / 0.35)
        score = area_ratio * (1.0 + continuity * 0.85)
        score += max(0.0, 1.0 - center_distance / 0.5) * 0.012
        if score <= best_score:
            continue
        best_score = score
        best = FocusSample(
            x=max(0.0, min(x, 1.0)),
            y=max(0.0, min(y, 1.0)),
            weight=max(0.001, math.sqrt(area_ratio) * (1.0 + continuity * 0.4)),
        )
    return best


def _intersection_over_union(
    left: tuple[int, int, int, int],
    right: tuple[int, int, int, int],
) -> float:
    left_x, left_y, left_width, left_height = left
    right_x, right_y, right_width, right_height = right
    overlap_width = max(
        0,
        min(left_x + left_width, right_x + right_width) - max(left_x, right_x),
    )
    overlap_height = max(
        0,
        min(left_y + left_height, right_y + right_height) - max(left_y, right_y),
    )
    overlap = overlap_width * overlap_height
    union = left_width * left_height + right_width * right_height - overlap
    return overlap / union if union > 0 else 0.0


def _deduplicate_faces(
    faces: list[tuple[int, int, int, int]],
) -> list[tuple[int, int, int, int]]:
    output: list[tuple[int, int, int, int]] = []
    for face in sorted(faces, key=lambda item: item[2] * item[3], reverse=True):
        if any(_intersection_over_union(face, existing) >= 0.35 for existing in output):
            continue
        output.append(face)
    return output


def _detect_faces(
    gray: Any,
    frontal_detector: Any,
    profile_detector: Any,
    minimum: int,
    cv2: Any,
) -> list[tuple[int, int, int, int]]:
    frame_width = int(gray.shape[1])
    detected: list[tuple[int, int, int, int]] = []
    for detector, image, mirrored in [
        (frontal_detector, gray, False),
        (profile_detector, gray, False),
        (profile_detector, cv2.flip(gray, 1), True),
    ]:
        faces = detector.detectMultiScale(
            image,
            scaleFactor=1.08,
            minNeighbors=4,
            minSize=(minimum, minimum),
        )
        for face in faces:
            left, top, width, height = (int(value) for value in face)
            if mirrored:
                left = frame_width - left - width
            detected.append((left, top, width, height))
    return _deduplicate_faces(detected)


def _focus_from_samples(
    samples: list[FocusSample],
    sample_count: int,
) -> tuple[float, float, float]:
    if not samples or sample_count <= 0:
        return 0.5, 0.42, 0.0
    coverage = len(samples) / sample_count
    average_weight = sum(item.weight for item in samples) / len(samples)
    confidence = min(1.0, coverage * 0.82 + min(average_weight / 0.22, 1.0) * 0.18)
    raw_x = _weighted_median(((item.x, item.weight) for item in samples), 0.5)
    raw_y = _weighted_median(((item.y, item.weight) for item in samples), 0.42)
    blend = min(1.0, 0.45 + confidence * 0.75)
    focus_x = 0.5 + (raw_x - 0.5) * blend
    focus_y = 0.42 + (raw_y - 0.42) * blend
    return (
        max(0.08, min(focus_x, 0.92)),
        max(0.12, min(focus_y, 0.78)),
        confidence,
    )


def _focus_keyframes_from_samples(
    samples: list[tuple[float, FocusSample]],
    duration: float,
) -> list[dict[str, float]]:
    if not samples or duration <= 0:
        return []
    ordered = sorted(samples, key=lambda item: item[0])
    reduced: list[tuple[float, FocusSample]] = []
    for seconds, sample in ordered:
        clamped_time = max(0.0, min(float(seconds), duration))
        if reduced:
            previous = reduced[-1][1]
            if abs(previous.x - sample.x) < 0.025 and abs(previous.y - sample.y) < 0.03:
                continue
        reduced.append((clamped_time, sample))

    first = reduced[0][1]
    last = reduced[-1][1]
    keyframes = [{"time": 0.0, "x": first.x, "y": first.y}]
    for seconds, sample in reduced:
        if seconds <= 0.05 or seconds >= duration - 0.05:
            continue
        keyframes.append({"time": seconds, "x": sample.x, "y": sample.y})
    keyframes.append({"time": duration, "x": last.x, "y": last.y})
    return [
        {
            "time": round(item["time"], 4),
            "x": round(max(0.08, min(item["x"], 0.92)), 4),
            "y": round(max(0.12, min(item["y"], 0.78)), 4),
        }
        for item in keyframes[:48]
    ]


def analyze_highlight_framing(
    video_path: Path,
    highlights: list[dict[str, Any]],
    max_samples_per_segment: int = 24,
) -> list[dict[str, Any]]:
    if not highlights:
        return []

    import cv2

    cascade_root = Path(cv2.data.haarcascades)
    frontal_path = cascade_root / "haarcascade_frontalface_default.xml"
    profile_path = cascade_root / "haarcascade_profileface.xml"
    frontal_detector = cv2.CascadeClassifier(str(frontal_path))
    profile_detector = cv2.CascadeClassifier(str(profile_path))
    if frontal_detector.empty() or profile_detector.empty():
        raise RuntimeError(
            f"face detectors could not load: {frontal_path}, {profile_path}"
        )

    capture = cv2.VideoCapture(str(video_path))
    if not capture.isOpened():
        raise RuntimeError(f"video could not be opened for smart reframe: {video_path}")

    output: list[dict[str, Any]] = []
    try:
        for highlight in highlights:
            item = {**highlight}
            start = float(item.get("start", 0.0))
            end = float(item.get("end", start))
            times = _sample_times(start, end, max_samples_per_segment)
            samples: list[FocusSample] = []
            timed_samples: list[tuple[float, FocusSample]] = []
            previous_x: float | None = None
            for seconds in times:
                capture.set(cv2.CAP_PROP_POS_MSEC, seconds * 1000)
                ok, frame = capture.read()
                if not ok or frame is None:
                    continue
                frame_height, frame_width = frame.shape[:2]
                if frame_width <= 0 or frame_height <= 0:
                    continue
                scale = min(1.0, 720.0 / frame_width)
                if scale < 1.0:
                    frame = cv2.resize(
                        frame,
                        (max(1, int(frame_width * scale)), max(1, int(frame_height * scale))),
                        interpolation=cv2.INTER_AREA,
                    )
                    frame_height, frame_width = frame.shape[:2]
                gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
                gray = cv2.equalizeHist(gray)
                minimum = max(24, int(min(frame_width, frame_height) * 0.07))
                faces = _detect_faces(
                    gray,
                    frontal_detector,
                    profile_detector,
                    minimum,
                    cv2,
                )
                sample = _choose_face(
                    faces,
                    frame_width,
                    frame_height,
                    previous_x,
                )
                if sample is None:
                    continue
                samples.append(sample)
                timed_samples.append((seconds - start, sample))
                previous_x = sample.x

            focus_x, focus_y, confidence = _focus_from_samples(samples, len(times))
            item["focus_x"] = round(focus_x, 4)
            item["focus_y"] = round(focus_y, 4)
            item["focus_confidence"] = round(confidence, 4)
            item["focus_keyframes"] = _focus_keyframes_from_samples(
                timed_samples,
                max(0.0, end - start),
            )
            tags = [str(tag) for tag in item.get("tags", []) if str(tag).strip()]
            framing_tag = "화자추적" if confidence >= 0.18 else "중앙구도"
            if framing_tag not in tags:
                tags.append(framing_tag)
            item["tags"] = tags
            output.append(item)
    finally:
        capture.release()
    return output
