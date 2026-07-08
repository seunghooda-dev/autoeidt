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

현재 데스크톱 편집 기능:

- 로컬 원본 Import: 백엔드 업로드 없이 PC 파일 경로를 직접 분석해 4GB 이상 원본도 처리
- 방송 원본 사전검사: FFprobe로 MXF/코덱/FPS/타임코드/오디오 스트림을 Import 직후 확인
- 프로젝트 상태 저장/불러오기: `.autoedit.json` 파일로 클립, 자막, 파형 상태 저장
- 오디오 파형 타임라인: 분석 완료 후 하단 타임라인에 파형 표시, 확대/축소 지원
- 트랙 제어: V1/A1/A2 타겟과 V1/A1/A2 개별 잠금, A1/A2 전체 뮤트/솔로, A/V 길이 싱크 자동수리 지원
- 클립 편집: In/Out, Lift/Extract, 추가, 선택 클립 적용, 삭제, split, 순서 이동
- 프레임 내비게이션: 30p 기준 Left/Right 1프레임 이동, Shift+Left/Right 10프레임 이동,
  Alt+Left/Right Slip 1프레임, Alt+Shift+Left/Right Slip 10프레임,
  Up/Down edit point 이동, Shift+I/O In/Out 점프, Home/End 시작/끝 이동
- 자동 자막: STT transcript 기반 자막 생성, 우측 `Captions` 탭에서 텍스트 수정/비활성화
- Export 모드: 16:9 유튜브용, 9:16 쇼츠용, 1:1 소셜용 mp4와 자막 burn-in 옵션
- 멀티 프로파일 익스포트: 같은 타임라인을 16:9/9:16/1:1 여러 납품 포맷으로 한 번에 batch 렌더
- 렌더 기준: 모든 프리뷰/최종 mp4는 30p non-drop으로 재인코딩하고 원본 timecode/drop-frame 메타데이터를 제거
- 뉴스형 AI 편집: 기관명/공식 출처/수치/발언이 함께 있는 `검증팩트` 구간을 우선 선별

지원 Import 컨테이너:

```text
mp4, mov, m4v, mkv, webm, avi, wmv, asf, mpg, mpeg, ts, m2ts, mts, flv, mxf
```

MXF는 FFmpeg가 읽을 수 있는 OP1a 계열 단일 파일을 우선 지원합니다. OP-Atom처럼
오디오가 별도 파일로 분리된 방송 원본은 사전검사에서 경고를 표시하며, 실제 분석 전
연결된 오디오 에센스 파일 확인이 필요합니다.

데스크톱 모드에서는 Redis/Celery 없이도 실행할 수 있도록 백엔드가
`TASK_RUNNER=inline` 모드를 지원합니다. Flutter 앱은 `http://localhost:8000/health`
상태를 확인한 뒤, 엔진이 꺼져 있으면 `scripts/start-desktop-engine.ps1`을 통해
로컬 FastAPI 엔진을 자동 실행합니다.

Windows 실행 파일 빌드에는 Visual Studio의 `Desktop development with C++`
워크로드가 필요합니다. Windows 앱의 영상 프리뷰는 `video_player_media_kit`과
`media_kit_libs_windows_video` 백엔드를 사용합니다.

OpenAI API 키가 없어도 데스크톱 엔진은 `faster-whisper` 로컬 STT를 우선 시도합니다.
처음 실행 시 모델 파일을 내려받으며, 이후에는 PC CPU/GPU로 음성 인식을 수행합니다.
기본 무료 모드는 `LOCAL_WHISPER_MODEL=tiny`, `LOCAL_WHISPER_DEVICE=cpu`, `LOCAL_WHISPER_COMPUTE_TYPE=int8`입니다.
정확도가 더 필요하면 `small` 또는 `medium`으로 올릴 수 있지만 처리 시간과 메모리 사용량이 늘어납니다.
OpenAI 키가 있으면 OpenAI STT/LLM을 우선 사용하고, 키가 없으면 로컬 STT와 내장 편집
스킬 엔진으로 동작합니다.

로컬 PC에서 빌드 도구를 설치하려면 관리자 권한 승인 후 아래 스크립트를 실행합니다.

```powershell
.\scripts\install-windows-build-tools.ps1 -Passive
```

Windows 패키지를 만들려면 아래 스크립트를 사용합니다.

```powershell
.\scripts\build-windows.ps1
```

빌드가 끝나면 실행 파일과 zip 패키지는 다음 위치에 생성됩니다.

```text
frontend\build\windows\x64\runner\Release\AutoEdit.exe
dist\AutoEdit-windows-x64.zip
```

로컬에 Visual Studio C++ 빌드 도구를 설치하지 못하는 경우, GitHub Actions의
`Windows Release Build` 워크플로를 실행하면 `AutoEdit-windows-x64` artifact가
생성됩니다.

## 백엔드 API 계약

- `POST /api/jobs/upload`: multipart 영상 업로드, 비동기 분석 작업 생성
- `POST /api/jobs/probe-local`: 로컬 원본의 컨테이너/코덱/FPS/타임코드/MXF 상태 사전검사
- `POST /api/jobs/import-local`: 로컬 PC 파일 경로 기반 분석 작업 생성
- `GET /api/jobs/{job_id}`: 작업 상태, 진행률, 메시지 조회
- `GET /api/jobs/{job_id}/timeline`: 분석 완료 후 타임라인 조회
- `GET /api/jobs/{job_id}/source`: 업로드 원본 영상 미리보기 스트림
- `POST /api/jobs/{job_id}/render`: 조정된 구간으로 최종 렌더링 요청
- `POST /api/jobs/{job_id}/batch-render`: 여러 쇼츠 후보 또는 여러 aspect ratio 프로파일 일괄 렌더링 요청
- `GET /api/jobs/{job_id}/download`: 렌더링된 mp4 다운로드

타임라인 구간 포맷:

```json
{
  "order": 1,
  "start": 124.5,
  "end": 155.2,
  "reason": "핵심 주제 결론 및 강조 부분",
  "script": "해당 구간 시작 스크립트",
  "source": "ai",
  "score": 8.5,
  "tags": ["핵심", "문제해결"]
}
```

## 자동 편집 스킬 엔진

LLM을 쓰지 못하는 환경에서도 단순 키워드 컷이 아니라 여러 신호를 합산해
하이라이트 후보를 고릅니다. 현재 내장 스킬은 핵심 키워드, 문제/해결 구조,
질문형 후킹, 숫자 기반 구체성, 정보 밀도, 감정 표현, 논리 전환점을 평가합니다.
뉴스/보도형 콘텐츠에서는 리드, 시간축, 출처 확인, 근거 자료, 피해와 영향,
공식 대응/반론, 직접 발언을 별도로 가중치화하고, 루머/미확인 주장, 말버릇,
콜투액션성 구간은 감점합니다. 선택 단계에서도 단순 점수순이 아니라
`뉴스핵심 -> 근거 -> 영향 -> 대응` 구조가 가능한 한 포함되도록 후보를 조합합니다.
LLM을 사용하는 경우에도 같은 스킬 점수로 결과를 보강해 프론트엔드에
`score`와 `tags`를 함께 전달합니다.

외부 분석 스킬은 Python 파일 또는 폴더를 `AUTOEDIT_ANALYSIS_SKILL_PATHS`에
연결하면 됩니다. 여러 경로는 Windows에서 세미콜론(`;`)으로 구분합니다.

```powershell
$env:AUTOEDIT_ANALYSIS_SKILL_PATHS="C:\Users\seung\auto edit\backend\examples\analysis_skills"
.\scripts\start-desktop-engine.ps1
```

외부 스킬 파일은 `create_skill()` 또는 `SKILL` 객체를 제공하고, `analyze(window)`
메서드에서 `SkillSignal(score, tag, reason)`을 반환하면 됩니다. 예시는
`backend\examples\analysis_skills\youtube_retention_skill.py`에 있습니다.

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

OpenAI 키가 없으면 백엔드는 로컬 `faster-whisper` STT를 먼저 사용합니다. 로컬 모델 설치나 실행에 실패하면 앱은 검토용 후보만 생성하고 경고를 표시합니다.
