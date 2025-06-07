from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import google.generativeai as genai
import os
import aiofiles
from datetime import datetime
import json
from typing import List, Dict

GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY")
if not GEMINI_API_KEY:
    raise ValueError("GEMINI_API_KEY 환경 변수가 설정되지 않았습니다.")

genai.configure(api_key=GEMINI_API_KEY)

app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

UPLOAD_DIR = "temp_uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)

model = genai.GenerativeModel("gemini-2.0-flash")


def get_today_date_str() -> str:
    return datetime.now().strftime("%Y%m%d")


async def classify_by_summary_with_gemini(summaries: List[Dict[str, str]]) -> Dict:
    classification_template = {
        "강의": {
            "{과목명1}": {
                "강의자료": ["강의자료.pdf"],
                "과제": ["과제.pdf"],
            },
            "{과목명2}}": {
                "강의자료": ["강의자료1.pdf", "강의자료2.pdf"],
                "과제": ["과제.pdf"],
            },
        },
        "프로젝트": {   
            "{프로젝트A}": {
                "기획": ["브레인스토밍.txt", "기획_요약.pdf"],
                "디자인": ["와이어프레임.png"],
                "개발": {
                    "frontend": [],
                    "backend": []
                },
                "결과물": ["테스트_리포트.pdf", "발표자료.pptx"]
            },
            "{프로젝트B}": {
                "요구사항명세서.docx": [],
                "코드": ["module1.js", "module2.js"]
            }
        },
        "포트폴리오": {
            "{포트폴리오A}": {
                "{공모전명1}": ["제안서.docx", "시연영상.mp4"],
                "{공모전명2}": ["수상증명서.pdf"]
            },
            "{대외활동A}": {
                "{회사명}": ["업무보고서.docx", "인터뷰_영상.mov"]
            },
            "{동아리A}": {
                "{동아리명1}_연간보고.xlsx": [],
                "{동아리명2}_포스터.jpg": []
            }
        },
        "일상": {
            "사진": [],
        },
        "기타_자료": ["{증빙서류}", "{참고문헌}", "{스크랩파일}"]
    }

    summary_lines = []
    for entry in summaries:
        txt = entry["summary"]
        summary_lines.append(f"- {txt}")

    prompt = f"""
    당신은 파일 정리 전문가입니다. 아래는 사용자가 업로드한 파일들의 요약문 목록입니다.
    각 파일이 어떤 종류의 자료인지 판단하여, 아래의 분류 템플릿(JSON 구조)에 맞추어 파일명을 분류해 주세요.

    요약문 목록:
    {chr(10).join(summary_lines)}

    분류 템플릿 예시 (JSON):
    {json.dumps(classification_template, ensure_ascii=False, indent=2)}

    출력은 반드시 JSON 형식으로, 상위 키(강의, 프로젝트, 포트폴리오_and_대외활동, 일상_and_학교생활, 기타_자료)를 유지한 채로 반환해 주세요.
    마크다운 코드 블럭 없이 순수한 json 내용만 반환해 주세요.

    (※다시 강조: 출력 시 ```json 또는 ``` 같은 마크다운 기호를 일체 사용하지 말고,
    첫 글자부터 '{' 로 시작해서 '}' 로 끝나는 유효한 JSON만 내보내주세요.)

    """

    try:
        response = await model.generate_content_async([prompt])
        raw_text = response.text.strip()

        # 1) ```json … ``` 페어가 있으면 제거
        if raw_text.startswith("```json"):
            raw_text = raw_text[len("```json"):]

        if raw_text.endswith("```"):
            raw_text = raw_text[: -3]

        # 2) 다시 공백 제거
        raw_text = raw_text.strip()

        # 3) 이제 순수 JSON으로 파싱
        classification_result = json.loads(raw_text)

    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Gemini 분류 요청 또는 JSON 파싱 실패: {e}\n응답 원문:\n{response.text}"
        )

    return classification_result


def generate_markdown_summary(spec: Dict) -> str:
    lines: List[str] = ["# 파일 정리 요약\n"]

    # 1. 강의
    lectures = spec.get("강의", {})
    lines.append("## 강의")
    if lectures:
        for subj, detail in lectures.items():
            lines.append(f"- {subj}")
            # 강의자료
            lec_files = detail.get("강의자료", [])
            lines.append(f"  - 강의자료 ({len(lec_files)}개)")
            for f in lec_files:
                lines.append(f"    - {f}")
            # 과제
            hw_files = detail.get("과제", [])
            lines.append(f"  - 과제 ({len(hw_files)}개)")
            for f in hw_files:
                lines.append(f"    - {f}")
    else:
        lines.append("- 없음")
    lines.append("")

    # 2. 프로젝트
    projects = spec.get("프로젝트", {})
    lines.append("## 프로젝트")
    if projects:
        for proj_name, details in projects.items():
            lines.append(f"- {proj_name}")
            for category, items in details.items():
                # 개발 카테고리 처리
                if category == "개발" and isinstance(items, dict):
                    lines.append(f"  - 개발")
                    for subdev, subitems in items.items():
                        lines.append(f"    - {subdev} ({len(subitems)}개)")
                        for f in subitems:
                            lines.append(f"      - {f}")
                else:
                    flist = items if isinstance(items, list) else []
                    lines.append(f"  - {category} ({len(flist)}개)")
                    for f in flist:
                        lines.append(f"    - {f}")
    else:
        lines.append("- 없음")
    lines.append("")

    # 3. 포트폴리오
    portfolio = spec.get("포트폴리오", {})
    lines.append("## 포트폴리오")
    if portfolio:
        for section, content in portfolio.items():
            lines.append(f"- {section}")
            for subcategory, files in content.items():
                flist = files if isinstance(files, list) else []
                lines.append(f"  - {subcategory} ({len(flist)}개)")
                for f in flist:
                    lines.append(f"    - {f}")
    else:
        lines.append("- 없음")
    lines.append("")

    # 4. 일상
    daily = spec.get("일상", {})
    lines.append("## 일상")
    if daily:
        for category, files in daily.items():
            flist = files if isinstance(files, list) else []
            lines.append(f"- {category} ({len(flist)}개)")
            for f in flist:
                lines.append(f"  - {f}")
    else:
        lines.append("- 없음")
    lines.append("")

    # 5. 기타_자료
    others = spec.get("기타_자료", [])
    lines.append(f"## 기타_자료 ({len(others)}개)")
    for f in others:
        lines.append(f"- {f}")
    lines.append("")

    return "\n".join(lines)



@app.post("/upload_and_classify")
async def upload_and_classify(files: List[UploadFile] = File(...)):
    summaries: List[Dict[str, str]] = []
    uploaded_file_paths: List[str] = []
    gemini_file_uris: List[str] = []

    try:
        for upload in files:
            destination_path = os.path.join(UPLOAD_DIR, upload.filename)
            uploaded_file_paths.append(destination_path)

            async with aiofiles.open(destination_path, "wb") as out_file:
                while content := await upload.read(1024 * 1024):
                    await out_file.write(content)

        for path in uploaded_file_paths:
            try:
                uploaded_file_info = genai.upload_file(path=path)
                gemini_file_uris.append(uploaded_file_info)
            except Exception as e:
                raise HTTPException(
                    status_code=500,
                    detail=f"파일 업로드 실패: {os.path.basename(path)} ({e})"
                )

        summary_prompt_template = """
                    당신은 다양한 파일을 분석하고 요약하는 전문가입니다.
                    사용자의 파일을 자동 분류하기 위해, 문서의 내용을 한눈에 파악하여 분류할 수 있도록 요약을 생성하는 역할을 맡고 있습니다.
                    파일 당 요약은 최대 2문장을 사용하세요.
                    문장마다 “마침표(.)”는 한 번만 찍고, 총 두 개의 문장으로 끝내야 합니다.

                    파일을 반드시 열어서 내용을 끝까지 확인한 뒤 요약을 진행하세요.
                    개별 요소를 따로 요약하는 게 아니라 파일 전체가 어떤 맥락이나 상황을 나타내고 있는지에 대해서 요약하세요.

                    [예시 출력 포맷]
                    [입력] 음식점들에 대한 이름, 위치, 전화번호, 주소, 영업시간 등 정보를 담고 있는 문서.
                    [출력] 음식점에 대한 정보를 담고 있는 문서입니다. 이름, 위치, 전화번호, 주소, 영업시간 등의 정보를 포함하고 있습니다."

                    다음은 요약할 파일의 URI입니다. URI의 파일을 읽고 해당 파일을 간결하게 요약하세요.
"""
        for idx, file_uri in enumerate(gemini_file_uris):
            filename = os.path.basename(uploaded_file_paths[idx])
            try:
                response = await model.generate_content_async([file_uri, summary_prompt_template])
                raw_text = response.text.strip()
                if raw_text.startswith(f"{filename} -"):
                    summaries.append({"filename": filename, "summary": raw_text})
                else:
                    summaries.append({"filename": filename, "summary": f"{filename} - {raw_text}"})
            except Exception as e:
                summaries.append({"filename": filename, "summary": f"요약 실패: {e}"})

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"백엔드 처리 중 오류 발생: {e}")

    finally:
        for path in uploaded_file_paths:
            if os.path.exists(path):
                os.remove(path)

    try:
        organization_spec = await classify_by_summary_with_gemini(summaries)
    except HTTPException as e:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"분류 중 예기치 않은 오류: {e}")

    markdown_summary = generate_markdown_summary(organization_spec)

    return JSONResponse(
        content={
            "summaries": summaries,
            "organization_spec": organization_spec,
            "markdown_summary": markdown_summary
        }
    )
