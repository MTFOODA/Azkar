#!/usr/bin/env python3
"""Build the editable AZKAR user guide and its PDF edition."""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from html.parser import HTMLParser
from pathlib import Path
from typing import Any

from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor
from PIL import Image, ImageDraw, ImageFont


GUIDE_DIR = Path(__file__).resolve().parent
SOURCE_HTML = GUIDE_DIR / "AZKAR_Arabic_User_Guide.html"
OUTPUT_DOCX = GUIDE_DIR / "AZKAR_Arabic_User_Guide.docx"
OUTPUT_PDF = GUIDE_DIR / "AZKAR_Arabic_User_Guide.pdf"
ARABIC_DIGITS = str.maketrans("0123456789", "٠١٢٣٤٥٦٧٨٩")
SCREENSHOT_DIR = GUIDE_DIR / "screenshots"


def set_rtl(paragraph: Any) -> None:
    paragraph.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    paragraph._p.get_or_add_pPr().append(OxmlElement("w:bidi"))


def set_font(style: Any, name: str, size: int, color: str | None = None) -> None:
    style.font.name = name
    style.font.size = Pt(size)
    if color:
        style.font.color.rgb = RGBColor.from_string(color)
    r_pr = style._element.get_or_add_rPr()
    fonts = r_pr.rFonts
    if fonts is None:
        fonts = OxmlElement("w:rFonts")
        r_pr.insert(0, fonts)
    for attribute in ("ascii", "hAnsi", "eastAsia", "cs"):
        fonts.set(qn(f"w:{attribute}"), name)


def set_run_properties(run: Any, *, bold: bool, italic: bool, underline: bool) -> None:
    run.bold = bold
    run.italic = italic
    run.underline = underline
    r_pr = run._element.get_or_add_rPr()
    rtl = OxmlElement("w:rtl")
    rtl.set(qn("w:val"), "1")
    r_pr.append(rtl)
    lang = OxmlElement("w:lang")
    lang.set(qn("w:val"), "ar-SA")
    lang.set(qn("w:bidi"), "ar-SA")
    r_pr.append(lang)
    fonts = r_pr.rFonts
    if fonts is None:
        fonts = OxmlElement("w:rFonts")
        r_pr.insert(0, fonts)
    for attribute in ("ascii", "hAnsi", "eastAsia", "cs"):
        fonts.set(qn(f"w:{attribute}"), "Tahoma")


def add_page_field(paragraph: Any) -> None:
    run = paragraph.add_run()
    begin = OxmlElement("w:fldChar")
    begin.set(qn("w:fldCharType"), "begin")
    instruction = OxmlElement("w:instrText")
    instruction.set(qn("xml:space"), "preserve")
    instruction.text = " PAGE "
    separate = OxmlElement("w:fldChar")
    separate.set(qn("w:fldCharType"), "separate")
    page_number = OxmlElement("w:t")
    page_number.text = "1"
    end = OxmlElement("w:fldChar")
    end.set(qn("w:fldCharType"), "end")
    run._r.extend((begin, instruction, separate, page_number, end))
    set_run_properties(run, bold=False, italic=False, underline=False)


def add_marker(draw: ImageDraw.ImageDraw, x: int, y: int, number: int) -> None:
    radius = 14
    draw.ellipse(
        (x - radius - 2, y - radius - 2, x + radius + 2, y + radius + 2),
        fill="white",
    )
    draw.ellipse(
        (x - radius, y - radius, x + radius, y + radius),
        fill="#c9a52f",
        outline="#052e25",
        width=2,
    )
    font = ImageFont.load_default()
    text = str(number)
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    draw.text(
        (x - (right - left) / 2, y - (bottom - top) / 2 - top),
        text,
        fill="#052e25",
        font=font,
    )


def annotate_screenshots() -> None:
    specifications = {
        "01-homepage.png": {
            "output": "01-homepage-annotated.png",
            "size": (390, 844),
            "markers": [(31, 78)],
            "highlight": (17, 15, 44, 43),
            "arrow": ((31, 62), (31, 43)),
        },
        "03-registration.png": {
            "output": "03-registration-annotated.png",
            "size": (873, 653),
            "markers": [(228, y) for y in (238, 331, 397, 463, 533)],
        },
        "09-tasbeeh.png": {
            "output": "09-tasbeeh-annotated.png",
            "size": (873, 653),
            "markers": [(71, 607)],
            "highlight": (51, 569, 390, 646),
        },
    }

    for source_name, specification in specifications.items():
        source = SCREENSHOT_DIR / source_name
        output = SCREENSHOT_DIR / specification["output"]
        if not source.is_file():
            raise FileNotFoundError(f"Guide screenshot does not exist: {source}")
        with Image.open(source) as source_image:
            if source_image.size != specification["size"]:
                raise ValueError(
                    f"Unexpected dimensions for {source}: "
                    f"{source_image.size}; expected {specification['size']}"
                )
            image = source_image.convert("RGB")
        draw = ImageDraw.Draw(image)
        if "highlight" in specification:
            draw.rectangle(specification["highlight"], outline="#c9a52f", width=3)
        if "arrow" in specification:
            draw.line(specification["arrow"], fill="white", width=5)
            draw.line(specification["arrow"], fill="#052e25", width=2)
        for number, (x, y) in enumerate(specification["markers"], start=1):
            add_marker(draw, x, y, number)
        image.save(output, format="PNG", optimize=True)


class GuideParser(HTMLParser):
    """Translate the guide's small, controlled HTML subset into Word."""

    block_tags = {"div", "figcaption", "h1", "h2", "h3", "li", "p"}

    def __init__(self, document: Any) -> None:
        super().__init__(convert_charrefs=True)
        self.document = document
        self.block: dict[str, Any] | None = None
        self.inline_bold = 0
        self.inline_italic = 0
        self.link_depth = 0
        self.list_stack: list[dict[str, Any]] = []
        self.cover_depth = 0
        self.callout_depth = 0
        self.chapter_count = 0
        self.image_count = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = dict(attrs)
        classes = set((attributes.get("class") or "").split())

        if tag == "section":
            if "cover" in classes:
                self.cover_depth += 1
            if "chapter" in classes:
                self.chapter_count += 1
                if self.chapter_count > 1:
                    self.document.add_page_break()
        elif tag == "nav" and "toc" in classes:
            pass
        elif tag in {"ol", "ul"}:
            self.list_stack.append({"kind": tag, "count": 0})
        elif tag == "div" and "callout" in classes:
            self.callout_depth += 1

        if tag == "a":
            self.link_depth += 1
        elif tag in {"strong", "b"}:
            self.inline_bold += 1
        elif tag in {"em", "i"}:
            self.inline_italic += 1
        elif tag == "br":
            if self.block is not None:
                self.block["runs"].append(("\n", False, False, False))
        elif tag == "img":
            self._add_image(attributes)
        elif tag in self.block_tags:
            self._flush_block()
            self.block = {
                "tag": tag,
                "classes": classes,
                "runs": [],
                "prefix": "",
            }
            if tag == "li" and self.list_stack:
                current_list = self.list_stack[-1]
                current_list["count"] += 1
                if current_list["kind"] == "ol":
                    self.block["prefix"] = (
                        f'{current_list["count"]}. '.translate(ARABIC_DIGITS)
                    )
                else:
                    self.block["prefix"] = "• "

    def handle_endtag(self, tag: str) -> None:
        if tag == "div":
            self._flush_block()
            self.callout_depth = max(0, self.callout_depth - 1)
        elif tag in self.block_tags:
            self._flush_block()
        elif tag == "a":
            self.link_depth = max(0, self.link_depth - 1)
        elif tag in {"strong", "b"}:
            self.inline_bold = max(0, self.inline_bold - 1)
        elif tag in {"em", "i"}:
            self.inline_italic = max(0, self.inline_italic - 1)
        elif tag in {"ol", "ul"} and self.list_stack:
            self.list_stack.pop()
        elif tag == "section":
            self.cover_depth = max(0, self.cover_depth - 1)
            if self.cover_depth == 0 and self.chapter_count == 0:
                self.document.add_page_break()
        elif tag == "nav":
            self.document.add_page_break()

    def handle_data(self, data: str) -> None:
        if self.block is not None and data:
            self.block["runs"].append(
                (data, self.inline_bold > 0, self.inline_italic > 0, self.link_depth > 0)
            )

    def _add_image(self, attributes: dict[str, str | None]) -> None:
        source = attributes.get("src")
        if not source:
            return
        image_path = (GUIDE_DIR / source).resolve()
        if not image_path.is_file():
            raise FileNotFoundError(f"Guide image does not exist: {image_path}")

        image_class = set((attributes.get("class") or "").split())
        width = Inches(1.7 if "cover-logo" in image_class else 2.7 if "portrait" in image_class else 5.8)
        paragraph = self.document.add_paragraph()
        paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
        run = paragraph.add_run()
        inline_shape = run.add_picture(str(image_path), width=width)
        description = attributes.get("alt") or ""
        if description:
            inline_shape._inline.docPr.set("descr", description)
        self.image_count += 1

    def _flush_block(self) -> None:
        if self.block is None:
            return
        block = self.block
        self.block = None
        tag = block["tag"]
        classes = block["classes"]

        if tag in {"div", "figcaption"} and not block["runs"]:
            return

        style_name = {
            "h1": "Title",
            "h2": "Heading 1",
            "h3": "Heading 2",
            "figcaption": "Caption",
        }.get(tag, "Normal")
        paragraph = self.document.add_paragraph(style=style_name)
        set_rtl(paragraph)
        paragraph.paragraph_format.keep_together = tag in {"h1", "h2", "h3", "li"}
        if tag in {"h1", "h2", "h3"}:
            paragraph.paragraph_format.keep_with_next = True
        if self.cover_depth:
            paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
        if tag == "li":
            paragraph.paragraph_format.right_indent = Inches(0.15)
            paragraph.paragraph_format.first_line_indent = Inches(-0.15)
        if tag == "figcaption":
            paragraph.paragraph_format.space_before = Pt(4)
            paragraph.paragraph_format.space_after = Pt(12)
        if "callout" in classes or self.callout_depth:
            self._shade_paragraph(paragraph)

        if block["prefix"]:
            prefix = paragraph.add_run(block["prefix"])
            set_run_properties(prefix, bold=True, italic=False, underline=False)
            prefix.font.color.rgb = RGBColor.from_string("064E3B")

        for text, bold, italic, linked in block["runs"]:
            run = paragraph.add_run(text)
            set_run_properties(run, bold=bold, italic=italic, underline=linked)
            if tag == "figcaption":
                run.font.size = Pt(9)
                run.font.color.rgb = RGBColor.from_string("65756E")

    @staticmethod
    def _shade_paragraph(paragraph: Any) -> None:
        paragraph.paragraph_format.left_indent = Inches(0.12)
        paragraph.paragraph_format.right_indent = Inches(0.12)
        paragraph.paragraph_format.space_before = Pt(7)
        paragraph.paragraph_format.space_after = Pt(10)
        paragraph_properties = paragraph._p.get_or_add_pPr()
        shading = OxmlElement("w:shd")
        shading.set(qn("w:fill"), "EDF5F0")
        paragraph_properties.append(shading)


def configure_document(document: Any) -> None:
    section = document.sections[0]
    section.top_margin = Inches(0.78)
    section.bottom_margin = Inches(0.72)
    section.left_margin = Inches(0.78)
    section.right_margin = Inches(0.78)

    styles = document.styles
    set_font(styles["Normal"], "Tahoma", 11, "26352F")
    styles["Normal"].paragraph_format.space_after = Pt(8)
    styles["Normal"].paragraph_format.line_spacing = 1.35
    set_font(styles["Title"], "Tahoma", 28, "052E25")
    set_font(styles["Heading 1"], "Tahoma", 18, "064E3B")
    set_font(styles["Heading 2"], "Tahoma", 14, "064E3B")
    set_font(styles["Caption"], "Tahoma", 9, "65756E")

    header = section.header.paragraphs[0]
    set_rtl(header)
    header.paragraph_format.space_after = Pt(4)
    header_run = header.add_run("أذكار | دليل المستخدم")
    set_run_properties(header_run, bold=True, italic=False, underline=False)
    header_run.font.size = Pt(9)
    header_run.font.color.rgb = RGBColor.from_string("064E3B")

    footer = section.footer.paragraphs[0]
    set_rtl(footer)
    footer.alignment = WD_ALIGN_PARAGRAPH.CENTER
    footer_run = footer.add_run("صفحة ")
    set_run_properties(footer_run, bold=False, italic=False, underline=False)
    footer_run.font.size = Pt(9)
    footer_run.font.color.rgb = RGBColor.from_string("65756E")
    add_page_field(footer)


def build_docx() -> None:
    document = Document()
    configure_document(document)
    parser = GuideParser(document)
    parser.feed(SOURCE_HTML.read_text(encoding="utf-8"))
    parser.close()
    parser._flush_block()
    document.core_properties.title = "أذكار | دليل المستخدم"
    document.core_properties.subject = "دليل عربي لإدارة صفحات أذكار"
    document.core_properties.author = "AZKAR"
    document.save(OUTPUT_DOCX)
    if parser.image_count < 5:
        raise RuntimeError(f"Expected at least 5 guide images, found {parser.image_count}")


def find_edge() -> Path:
    candidates = [
        Path(os.environ.get("ProgramFiles(x86)", "C:/Program Files (x86)"))
        / "Microsoft/Edge/Application/msedge.exe",
        Path(os.environ.get("ProgramFiles", "C:/Program Files"))
        / "Microsoft/Edge/Application/msedge.exe",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    executable = shutil.which("msedge.exe")
    if executable:
        return Path(executable)
    raise FileNotFoundError("Microsoft Edge was not found; it is required to build the PDF.")


def build_pdf() -> None:
    edge = find_edge()
    with tempfile.TemporaryDirectory(prefix="azkar-guide-edge-") as profile_dir:
        command = [
            str(edge),
            "--headless=new",
            "--disable-gpu",
            "--disable-extensions",
            "--disable-background-networking",
            "--no-first-run",
            f"--user-data-dir={profile_dir}",
            f"--print-to-pdf={OUTPUT_PDF}",
            SOURCE_HTML.resolve().as_uri(),
        ]
        subprocess.run(command, check=True, timeout=120)
    if not OUTPUT_PDF.is_file() or OUTPUT_PDF.stat().st_size < 10_000:
        raise RuntimeError("Edge did not produce a valid-looking PDF.")


def main() -> None:
    annotate_screenshots()
    build_docx()
    build_pdf()
    print(f"Created: {OUTPUT_DOCX}")
    print(f"Created: {OUTPUT_PDF}")


if __name__ == "__main__":
    main()
