"""The analysis report as a PDF, built from the same data the app's report screen shows.

Two versions, decided by who asks, never by a parameter:
- doctor: model confidence, all class scores, override reason and clinical notes;
- patient (released results only): the classification, the doctor's decision and
  summary. No model confidence, no class scores, no doctor-only fields.

Times are written in the reader's local time when the app sends its UTC offset.
"""
import io
from datetime import datetime, timedelta, timezone

from PIL import Image as PILImage
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import (
    Flowable,
    Image,
    KeepTogether,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

from app.db.models import Analysis, Decision

LABELS = {
    "CN": "Cognitively Normal",
    "EMCI": "Early MCI",
    "LMCI": "Late MCI",
    "AD": "Alzheimer's Disease",
}
CLASS_ORDER = ("CN", "EMCI", "LMCI", "AD")

TEAL = colors.HexColor("#0E6B63")
NAVY = colors.HexColor("#14302E")
INK = colors.HexColor("#22302F")
MUTED = colors.HexColor("#5F6B6A")
AI = colors.HexColor("#5B4BC4")
AI_TINT = colors.HexColor("#EEEBFB")
DOCTOR = colors.HexColor("#1E7A4C")
DOCTOR_TINT = colors.HexColor("#E6F3EC")
AMBER = colors.HexColor("#B26A00")
AMBER_TINT = colors.HexColor("#FFF4DE")
LINE = colors.HexColor("#D9E1E0")
SURFACE_ALT = colors.HexColor("#EEF2F1")

DISCLAIMER = (
    "<b>Disclaimer.</b> This report contains an AI-assisted classification produced by an academic research "
    "system that is not a certified medical device. AI predictions are not standalone clinical diagnoses and "
    "must be interpreted by a qualified healthcare professional."
)

_base = ParagraphStyle("base", fontName="Helvetica", fontSize=10, leading=14, textColor=INK)
S = {
    "title": ParagraphStyle("title", parent=_base, fontName="Helvetica-Bold", fontSize=20, leading=24, textColor=NAVY),
    "subtitle": ParagraphStyle("subtitle", parent=_base, textColor=MUTED),
    "label": ParagraphStyle("label", parent=_base, fontSize=8.5, leading=11, textColor=MUTED),
    "value": ParagraphStyle("value", parent=_base, fontName="Helvetica-Bold", fontSize=10.5),
    "mono": ParagraphStyle("mono", parent=_base, fontName="Courier", fontSize=9.5, leading=13),
    "heading": ParagraphStyle(
        "heading", parent=_base, fontName="Helvetica-Bold", fontSize=9, leading=12, textColor=MUTED, spaceBefore=6
    ),
    "big": ParagraphStyle("big", parent=_base, fontName="Helvetica-Bold", fontSize=15, leading=19, textColor=NAVY),
    "body": _base,
    "caption": ParagraphStyle("caption", parent=_base, fontSize=8.5, leading=11, textColor=MUTED),
    "band": ParagraphStyle("band", parent=_base, fontName="Helvetica-Bold", fontSize=9, leading=12),
    "small": ParagraphStyle("small", parent=_base, fontSize=8.5, leading=12),
}


def _esc(text: str) -> str:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\n", "<br/>")


def _p(text: str, style: str = "body") -> Paragraph:
    return Paragraph(text, S[style])


def _band(title: str, fg, bg) -> Table:
    t = Table([[_p(f'<font color="{fg.hexval()}">{title}</font>', "band")]], colWidths=["100%"])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), bg),
        ("LEFTPADDING", (0, 0), (-1, -1), 8),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
    ]))
    return t


class _Bar(Flowable):
    """A horizontal score bar."""

    def __init__(self, value: float, width: float, color):
        super().__init__()
        self.value, self.width, self.height, self.color = max(0.0, min(1.0, value)), width, 5, color

    def draw(self):
        self.canv.setFillColor(SURFACE_ALT)
        self.canv.roundRect(0, 0, self.width, self.height, 2, stroke=0, fill=1)
        if self.value > 0:
            self.canv.setFillColor(self.color)
            self.canv.roundRect(0, 0, max(self.width * self.value, 2), self.height, 2, stroke=0, fill=1)


def _image(png: bytes, size: float) -> Image:
    return Image(io.BytesIO(png), width=size, height=size)


def _overlay_png(model_input: bytes, heatmap_colour: bytes, opacity: float = 0.4) -> bytes:
    """The Grad-CAM map over the image the model received, as the app's Overlay tab shows it."""
    with PILImage.open(io.BytesIO(model_input)) as base, PILImage.open(io.BytesIO(heatmap_colour)) as heat:
        base_rgb = base.convert("RGB")
        blended = PILImage.blend(base_rgb, heat.convert("RGB").resize(base_rgb.size), opacity)
    out = io.BytesIO()
    blended.save(out, format="PNG")
    return out.getvalue()


def _fmt(dt: datetime, offset: timedelta, with_time: bool = True) -> str:
    local = dt.astimezone(timezone(offset))
    text = f"{local.day} {local:%b %Y}"
    if with_time:
        text += f" · {local:%H:%M}"
        if offset == timedelta(0):
            text += " UTC"
    return text


def build_report(
    analysis: Analysis,
    *,
    for_patient: bool,
    generated_at: datetime,
    utc_offset: timedelta = timedelta(0),
) -> bytes:
    """The report for a REVIEWED analysis. The caller checks access and review state."""
    review = analysis.review
    assert review is not None, "reports exist only for reviewed analyses"
    patient = analysis.patient
    scan = analysis.scan
    width = A4[0] - 36 * mm

    story: list = []
    title = _p("NeuroSense", "title")
    subtitle = _p("AI-Assisted MRI Analysis Report · " + ("Patient copy" if for_patient else "Doctor version"),
                  "subtitle")
    story += [title, Spacer(1, 2), subtitle, Spacer(1, 6)]
    rule = Table([[""]], colWidths=[width], rowHeights=[2])
    rule.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), NAVY)]))
    story += [rule, Spacer(1, 8)]

    if analysis.simulated:
        warn = Table([[_p("<b>SIMULATED RESULT.</b> Produced without the real AI model; not a model output.",
                          "small")]], colWidths=[width])
        warn.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), AMBER_TINT),
                                  ("LINEBEFORE", (0, 0), (0, -1), 3, AMBER),
                                  ("LEFTPADDING", (0, 0), (-1, -1), 8)]))
        story += [warn, Spacer(1, 10)]

    def cell(label, value, style="value"):
        return [_p(label, "label"), _p(_esc(value), style)]

    grid = Table(
        [
            [cell("Patient", patient.user.full_name), cell("Patient ID", patient.display_id, "mono")],
            [cell("Analysis date", _fmt(analysis.created_at, utc_offset)),
             cell("Report ID", f"NSR-{str(analysis.id).upper()}", "mono")],
        ],
        colWidths=[width / 2, width / 2],
    )
    grid.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 0),
                              ("BOTTOMPADDING", (0, 0), (-1, -1), 6)]))
    story += [grid, Spacer(1, 8)]

    # ---------------------------------------------------------------- AI section
    story += [_band("AI-GENERATED INFORMATION", AI, AI_TINT), Spacer(1, 4)]
    story.append(_p("MRI information", "heading"))
    if scan is not None and scan.kind == "volume":
        mri = (f"Full MRI scan (NIfTI) · uploaded {_fmt(analysis.created_at, utc_offset)}. "
               f"The model's scores were averaged over {analysis.slices_used or '?'} of "
               f"{analysis.slices_total or '?'} axial slices; the image below is slice {analysis.slice_index}.")
    else:
        mri = f"Axial brain MRI slice (JPG/PNG) · uploaded {_fmt(analysis.created_at, utc_offset)}"
    story.append(_p(_esc(mri)))

    left: list = [_p("AI model prediction", "heading"), _p(_esc(LABELS.get(analysis.predicted_label,
                                                                            analysis.predicted_label)), "big")]
    if not for_patient:
        left += [
            _p("Model confidence", "heading"),
            _p(f"{analysis.confidence * 100:.1f}%", "big"),
            _p("Softmax score, not a calibrated probability.", "caption"),
            Spacer(1, 6),
        ]
        probs = analysis.probabilities or {}
        rows = []
        for code in CLASS_ORDER:
            value = float(probs.get(code, 0.0))
            top = code == analysis.predicted_label
            rows.append([
                _p(("<b>%s</b>" if top else "%s") % _esc(LABELS[code]), "small"),
                _Bar(value, 52 * mm, TEAL if top else MUTED),
                _p(f"{value * 100:.1f}%", "mono"),
            ])
        scores = Table(rows, colWidths=[38 * mm, 56 * mm, 18 * mm])
        scores.setStyle(TableStyle([
            ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 0),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"), ("ALIGN", (2, 0), (2, -1), "RIGHT"),
            ("TOPPADDING", (0, 0), (-1, -1), 2), ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
        ]))
        left.append(scores)

    has_map = (analysis.heatmap is not None and analysis.model_input is not None
               and analysis.explanation_method == "gradcam")
    left.append(_p("Model", "heading"))
    left.append(_p(_esc(f"{analysis.model_name} {analysis.model_version}"
                         + (" (placeholder)" if analysis.simulated else "")), "mono"))
    left.append(_p("Explainability", "heading"))
    if not has_map:
        left.append(_p("No explainability map is available for this result."))
    elif for_patient:
        left.append(_p("The coloured overlay shows where the computer model looked most when it made its "
                        "suggestion. It is not a diagnosis and does not show where disease or damage is."))
    else:
        left.append(_p("Grad-CAM heatmap for the predicted class (last convolutional block), shown over the "
                        "masked image the model received. Highlighted regions show where the model focused, "
                        "not medically proven causes, and carry no anatomical claim."))
    images: list = []
    if scan is not None and scan.image is not None:
        images += [_p("MRI slice", "label"), _image(scan.image, 38 * mm), Spacer(1, 4)]
    if has_map:
        from app.ml.gradcam import colour_heatmap_png

        overlay = _overlay_png(analysis.model_input, colour_heatmap_png(analysis.heatmap))
        images += [_p("Grad-CAM overlay", "label"), _image(overlay, 38 * mm)]
    top = Table([[left, images]], colWidths=[width - 42 * mm, 42 * mm])
    top.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 0)]))
    story.append(top)

    story.append(Spacer(1, 8))

    # ---------------------------------------------------------------- doctor section
    doctor_part: list = [_band("DOCTOR-REVIEWED INFORMATION", DOCTOR, DOCTOR_TINT), Spacer(1, 4)]
    decision = "AI result overridden" if review.decision == Decision.overridden else "Confirmed AI result"
    doctor_part += [
        _p("Doctor review", "heading"),
        _p(f"<b>{decision}</b> · {_esc(review.doctor.user.full_name)} · {_fmt(review.reviewed_at, utc_offset)}"),
        _p("Final classification", "heading"),
        _p(_esc(LABELS.get(review.final_label, review.final_label)), "value"),
    ]
    if not for_patient and review.override_reason:
        doctor_part += [_p("Reason for override", "heading"), _p(_esc(review.override_reason))]
    if not for_patient and review.clinical_notes:
        doctor_part += [_p("Clinical notes · clinicians only", "heading"), _p(_esc(review.clinical_notes))]
    if review.patient_summary:
        doctor_part += [_p("Patient summary", "heading"), _p(_esc(review.patient_summary))]
    if not for_patient:
        released = ("Released to patient " + _fmt(review.released_at, utc_offset)) if review.released_at \
            else "Not released to the patient"
        doctor_part += [_p("Release", "heading"), _p(released)]
    # The band stays with its first lines; the rest may continue on the next page.
    story += [KeepTogether(doctor_part[:4]), *doctor_part[4:], Spacer(1, 10)]

    note = Table([[_p(DISCLAIMER, "small")]], colWidths=[width])
    note.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), SURFACE_ALT), ("LEFTPADDING", (0, 0), (-1, -1), 10),
                              ("RIGHTPADDING", (0, 0), (-1, -1), 10), ("TOPPADDING", (0, 0), (-1, -1), 8),
                              ("BOTTOMPADDING", (0, 0), (-1, -1), 8)]))
    story.append(KeepTogether([note]))

    footer_text = f"Generated {_fmt(generated_at, utc_offset)} · NSR-{str(analysis.id).upper()}"

    def footer(canvas, doc):
        canvas.saveState()
        canvas.setFont("Courier", 7.5)
        canvas.setFillColor(MUTED)
        canvas.drawString(18 * mm, 10 * mm, footer_text)
        canvas.drawRightString(A4[0] - 18 * mm, 10 * mm, f"Page {doc.page}")
        canvas.restoreState()

    out = io.BytesIO()
    doc = SimpleDocTemplate(
        out, pagesize=A4, leftMargin=18 * mm, rightMargin=18 * mm, topMargin=14 * mm, bottomMargin=16 * mm,
        title=f"NeuroSense report NSR-{str(analysis.id).upper()}", author="NeuroSense", creator="NeuroSense",
        pageCompression=0,  # text stays searchable in tests; the pages are small anyway
    )
    doc.build(story, onFirstPage=footer, onLaterPages=footer)
    return out.getvalue()
