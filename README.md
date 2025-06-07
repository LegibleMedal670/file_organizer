# file_organizer

간단한 LLM 기반 파일 자동 정리 도구

---

## 🔎 프로젝트 개요
Flutter 데스크톱 애플리케이션과 FastAPI 서버를 연동하여, 사용자가 드래그&드롭한 파일을 AI(Google Gemini)로 요약·분류하고, 지정된 폴더 구조에 맞춰 원본 파일 이름을 그대로 유지한 채 자동으로 이동·정리해 줍니다.

## ✨ 주요 기능
- **Drag & Drop**: 데스크톱 앱에 파일이나 폴더를 끌어다 놓기
- **LLM 요약·분류**: Google Gemini API를 이용해 파일 내용 메타데이터(요약·키워드·카테고리) 생성
- **JSON 명세**: 분류 결과를 JSON 형태로 반환
- **폴더 생성 및 이동**: JSON 명세에 따라 폴더 생성 후 원본 파일을 이동

## 🛠️ 기술 스택
- **클라이언트**: `Flutter` (Dart)
- **서버**: `FastAPI` (Python)
- **AI 연동**: `google-generative-ai` (Gemini API)
