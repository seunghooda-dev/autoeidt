# AI 기반 롱폼 영상 하이라이트 자동 편집기

1시간 내외의 원본 영상을 업로드하면 백엔드가 STT, LLM 분석, 침묵 제거, 시각 변화 보호 로직을 거쳐 3-4분 하이라이트 타임라인을 생성하고, Flutter 앱에서 미세 조정 후 최종 mp4를 렌더링하는 프로젝트입니다.

## 구조

- `backend/`: FastAPI + Celery + Redis + FFmpeg 기반 에디팅 엔진
- `frontend/`: Flutter + Provider + Dio + video_player 기반 데스크톱/웹 편집 UI
- `scripts/start-desktop-engine.ps1`: Windows 데스크톱 앱용 로컬 백엔드 엔진 실행 스크립트
- `docker-compose.yml`: Redis, API, Worker 실행 구성

## 데스크톱 앱 방향

Windows 데스크톱 앱은 CapCut 계열 편집 툴처럼 좌측 미디어 패널, 중앙 프리뷰,
우측 AI 클립 인스펙터, 하단 타임라인 도크 구조로 구성합니다.

데스크톱 모드에서는 Redis/Celery 없이도 실행할 수 있도록 백엔드가
`TASK_RUNNER=inline` 모드를 지원합니다. Flutter 앱은 `http://localhost:8000/health`
상태를 확인한 뒤, 엔진이 꺼져 있으면 `scripts/start-desktop-engine.ps1`을 통해
로컬 FastAPI 엔진을 자동 실행합니다.

Windows 실행 파일 빌드에는 Visual Studio의 `Desktop development with C++`
워크로드가 필요합니다. Windows 앱의 영상 프리뷰는 `video_player_media_kit`과
`media_kit_libs_windows_video` 백엔드를 사용합니다.

```powershell
cd "C:\Users\seung\auto edit\frontend"
flutter config --enable-windows-desktop
flutter build windows --dart-define=API_BASE_URL=http://localhost:8000
```

빌드가 끝나면 실행 파일은 다음 위치에 생성됩니다.

```text
frontend\build\windows\x64\runner\Release\AutoEdit.exe
```

## 백엔드 API 계약

- `POST /api/jobs/upload`: multipart 영상 업로드, 비동기 분석 작업 생성
- `GET /api/jobs/{job_id}`: 작업 상태, 진행률, 메시지 조회
- `GET /api/jobs/{job_id}/timeline`: 분석 완료 후 타임라인 조회
- `GET /api/jobs/{job_id}/source`: 업로드 원본 영상 미리보기 스트림
- `POST /api/jobs/{job_id}/render`: 조정된 구간으로 최종 렌더링 요청
- `GET /api/jobs/{job_id}/download`: 렌더링된 mp4 다운로드

타임라인 구간 포맷:

```json
{
  "order": 1,
  "start": 124.5,
  "end": 155.2,
  "reason": "핵심 주제 결론 및 강조 부분",
  "script": "해당 구간 시작 스크립트",
  "source": "ai"
}
```

## Docker 실행

루트에 `.env`를 만들고 `.env.example` 내용을 복사한 뒤 필요하면 `OPENAI_API_KEY`를 입력합니다.

```powershell
docker compose up --build
```

API는 `http://localhost:8000`, 상태 확인은 `http://localhost:8000/health`입니다.

## 로컬 백엔드 실행

Python은 3.12 사용을 권장합니다. 현재 Python 3.14는 일부 AI/영상 라이브러리 휠 호환성이 깨질 수 있습니다.

데스크톱 앱용 단일 프로세스 엔진은 아래 스크립트로 실행할 수 있습니다.

```powershell
.\scripts\start-desktop-engine.ps1
```

서버형 Celery 구성을 수동 실행하려면 아래 방식을 사용합니다.

```powershell
cd "C:\Users\seung\auto edit\backend"
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

별도 터미널에서 Redis와 Worker가 필요합니다.

```powershell
celery -A app.celery_app.celery_app worker --loglevel=INFO --pool=solo
```

## Flutter 실행

```powershell
cd "C:\Users\seung\auto edit\frontend"
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

OpenAI 키가 없으면 백엔드는 개발용 스크립트와 휴리스틱 하이라이트를 생성합니다. 실제 품질 검증은 `.env`에 `OPENAI_API_KEY`를 설정한 뒤 진행해야 합니다.
