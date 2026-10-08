#!/usr/bin/env python3
"""Generates architecture.svg: python3 scripts/architecture.py > architecture.svg

Layout is a fixed grid; edit coordinates here, not in the SVG."""
import sys

INK, MUTED, FAINT, LINE = "#0f172a", "#64748b", "#94a3b8", "#cbd5e1"
CDK, CDK_TINT = "#0e9f6e", "#ecfdf5"
EXT_TINT = "#f1f5f9"
HTTPS, KAFKA, METRICS = "#2563eb", "#0f172a", "#94a3b8"
GROUP_FILL = "#f8fafc"

ICONS = {
    "apps": '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
    "user": '<circle cx="12" cy="8" r="4"/><path d="M4 21v-1a6 6 0 0 1 6-6h4a6 6 0 0 1 6 6v1"/>',
    "terminal": '<rect x="2.5" y="4" width="19" height="16" rx="2"/><path d="M7 9l3 3-3 3M13 15h4"/>',
    "lb": '<circle cx="12" cy="5" r="2"/><circle cx="5" cy="19" r="2"/><circle cx="12" cy="19" r="2"/><circle cx="19" cy="19" r="2"/><path d="M12 7v10M12 12H5v5M12 12h7v5"/>',
    "globe": '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
    "shield": '<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/><path d="M9 12l2 2 4-4"/>',
    "window": '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 9h18M6.5 6.5h.01M9.5 6.5h.01"/>',
    "chart": '<path d="M3 20h18M6 16v-4M10 16V8M14 16v-6M18 16V5"/>',
    "kafka": '<circle cx="9" cy="12" r="2.5"/><circle cx="9" cy="4" r="2"/><circle cx="9" cy="20" r="2"/><circle cx="17" cy="8" r="2"/><circle cx="17" cy="16" r="2"/><path d="M9 6v3.5M9 14.5V18M11.2 10.8l4-2M11.2 13.2l4 2"/>',
    "server": '<rect x="3" y="4" width="18" height="7" rx="1.5"/><rect x="3" y="13" width="18" height="7" rx="1.5"/><path d="M7 7.5h.01M7 16.5h.01"/>',
    "db": '<ellipse cx="12" cy="5" rx="8" ry="3"/><path d="M4 5v14c0 1.7 3.6 3 8 3s8-1.3 8-3V5"/><path d="M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3"/>',
    "bucket": '<ellipse cx="12" cy="6" rx="8" ry="2.5"/><path d="M4 6l2 13c.2 1.2 2.8 2 6 2s5.8-.8 6-2l2-13"/>',
    "key": '<circle cx="8" cy="15" r="4"/><path d="M10.8 12.2L20 3M16 7l3 3M14 9l2 2"/>',
    "id": '<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="9" cy="11" r="2"/><path d="M6 16c.6-1.5 1.7-2 3-2s2.4.5 3 2M14 10h4M14 14h3"/>',
    "braces": '<path d="M8 4H7a2 2 0 0 0-2 2v4a2 2 0 0 1-2 2 2 2 0 0 1 2 2v4a2 2 0 0 0 2 2h1M16 4h1a2 2 0 0 1 2 2v4a2 2 0 0 0 2 2 2 2 0 0 0-2 2v4a2 2 0 0 1-2 2h-1"/>',
    "cert": '<circle cx="12" cy="9" r="5"/><path d="M9 13.5L8 21l4-2 4 2-1-7.5"/>',
    "lock": '<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
    "pulse": '<path d="M3 12h4l3-8 4 16 3-8h4"/>',
    "logs": '<path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/><path d="M14 3v6h6M8 13h8M8 17h6"/>',
    "k8s": '<path d="M12 2.5l7.4 3.6 1.8 8-5.1 6.4H7.9l-5.1-6.4 1.8-8z"/><circle cx="12" cy="12" r="2.2"/><path d="M12 6v3.8M12 14.2V18M6.6 9.8l3.3 1.4M17.4 9.8l-3.3 1.4M8.5 16.5l2.2-2.6M15.5 16.5l-2.2-2.6"/>',
}

out = []
w = out.append


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def icon(name, x, y, size, color):
    w(f'<use xlink:href="#i-{name}" x="{x}" y="{y}" width="{size}" height="{size}" color="{color}"/>')


def node(x, y, wd, h, ic, title, sub=None, kind="ext", opt=False, badge=None):
    stroke = CDK if kind == "cdk" else LINE
    tint = CDK_TINT if kind == "cdk" else EXT_TINT
    icol = CDK if kind == "cdk" else MUTED
    dash = ' stroke-dasharray="5 4"' if opt else ""
    w(f'<rect x="{x}" y="{y}" width="{wd}" height="{h}" rx="4" fill="#fff" stroke="{stroke}" stroke-width="{1.5 if kind == "cdk" else 1.2}"{dash}/>')
    cy = y + h / 2
    w(f'<rect x="{x + 10}" y="{cy - 16}" width="32" height="32" rx="4" fill="{tint}"/>')
    icon(ic, x + 16, cy - 10, 20, icol)
    tx = x + 54
    if sub:
        w(f'<text x="{tx}" y="{cy - 3}" class="t">{esc(title)}</text>')
        w(f'<text x="{tx}" y="{cy + 13}" class="s">{esc(sub)}</text>')
    else:
        w(f'<text x="{tx}" y="{cy + 4}" class="t">{esc(title)}</text>')
    if badge:
        bw = 26
        w(f'<rect x="{x + wd - bw - 8}" y="{y + 8}" width="{bw}" height="16" rx="3" fill="{CDK_TINT}"/>')
        w(f'<text x="{x + wd - bw / 2 - 8}" y="{y + 20}" class="badge" text-anchor="middle">{badge}</text>')


def group(x, y, wd, h, label, ic=None, dashed=False, fill=GROUP_FILL):
    dash = ' stroke-dasharray="4 4"' if dashed else ""
    w(f'<rect x="{x}" y="{y}" width="{wd}" height="{h}" rx="6" fill="{fill}" stroke="{LINE}"{dash}/>')
    lx = x + 14
    if ic:
        icon(ic, lx, y + 9, 15, MUTED)
        lx += 21
    w(f'<text x="{lx}" y="{y + 21}" class="g">{esc(label)}</text>')


MARK = {"kafka": "ak", "https": "ah", "metrics": "am"}
COLOR = {"kafka": KAFKA, "https": HTTPS, "metrics": METRICS}


def edge(pts, kind, both=False):
    d = "M" + " L".join(f"{px},{py}" for px, py in pts)
    dash = ' stroke-dasharray="4 4"' if kind == "metrics" else ""
    start = f' marker-start="url(#{MARK[kind]})"' if both else ""
    w(f'<path d="{d}" fill="none" stroke="{COLOR[kind]}" stroke-width="1.5"{dash}{start} marker-end="url(#{MARK[kind]})"/>')


def label(x, y, text, kind, anchor="middle", bg="#fff"):
    tw = len(text) * 6.1 + 8
    rx = {"middle": x - tw / 2, "start": x - 4, "end": x - tw + 4}[anchor]
    w(f'<rect x="{rx:.1f}" y="{y - 11}" width="{tw:.1f}" height="15" fill="{bg}"/>')
    w(f'<text x="{x}" y="{y}" class="e" fill="{COLOR[kind]}" text-anchor="{anchor}">{esc(text)}</text>')


W, H = 1200, 790
TOP = 70  # vertical offset removed from the drawing area

w(f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 {W} {H}" width="{W}" height="{H}" '
  "font-family=\"Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Helvetica Neue', Arial, sans-serif\">")
w("<title>Conduktor Platform reference architecture</title>")
w(f"""<style>
.t{{font-size:13px;font-weight:600;fill:{INK}}}
.s{{font-size:11.5px;fill:{MUTED}}}
.g{{font-size:10.5px;font-weight:600;letter-spacing:.08em;fill:{MUTED}}}
.e{{font-size:11px;font-weight:500}}
.badge{{font-size:10.5px;font-weight:600;fill:{CDK}}}
.lg{{font-size:11.5px;fill:{MUTED}}}
</style>""")
w("<defs>")
for name, body in ICONS.items():
    w(f'<symbol id="i-{name}" viewBox="0 0 24 24"><g fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">{body}</g></symbol>')
for kind, mid in MARK.items():
    w(f'<marker id="{mid}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,1 L9,5 L0,9 z" fill="{COLOR[kind]}"/></marker>')
w("</defs>")
w(f'<rect width="{W}" height="{H}" fill="#fff"/>')

w(f'<g transform="translate(0,-{TOP})">')

# Legend
ly = TOP + 32
for x, kind, text in [(40, "kafka", "Kafka protocol"), (190, "https", "HTTPS"), (295, "metrics", "Metrics")]:
    edge([(x, ly), (x + 30, ly)], kind)
    w(f'<text x="{x + 40}" y="{ly + 4}" class="lg">{text}</text>')
for x, stroke, dash, text in [(420, CDK, "", "Conduktor"), (540, LINE, "", "Pre-existing"), (670, LINE, ' stroke-dasharray="4 3"', "Optional")]:
    w(f'<rect x="{x}" y="{ly - 7}" width="30" height="14" rx="3" fill="#fff" stroke="{stroke}" stroke-width="1.3"{dash}/>')
    w(f'<text x="{x + 40}" y="{ly + 4}" class="lg">{text}</text>')

# Groups
group(300, 128, 540, 484, "KUBERNETES  ·  namespace conduktor", "k8s")
group(880, 224, 280, 276, "KAFKA CLUSTER", "kafka")

# Clients
w('<text x="40" y="182" class="g">DATA PATH</text>')
node(40, 192, 200, 56, "apps", "Kafka applications", "producers, consumers")
w('<text x="40" y="386" class="g">MANAGEMENT PATH</text>')
node(40, 396, 200, 56, "terminal", "Automation", "Terraform, CLI, GitOps")
node(40, 468, 200, 56, "user", "Platform users", "browser, SSO")

# Conduktor
node(340, 192, 240, 56, "shield", "Conduktor Gateway", "stateless", kind="cdk", badge="×3")
node(340, 432, 240, 56, "window", "Conduktor Console", "UI, API, self-service", kind="cdk", badge="×2")
node(613, 520, 204, 56, "chart", "Console Cortex", "metrics store", kind="cdk", badge="×1")

# Kafka side
node(880, 150, 280, 56, "key", "KMS", "Vault, AWS, Azure, GCP", opt=True)
for i in range(3):
    node(896, 256 + i * 60, 248, 48, "server", f"broker-{i}")
w('<text x="896" y="456" class="s">+ Gateway internal topics</text>')
w('<text x="896" y="474" class="s">+ audit log topics</text>')
node(880, 624, 280, 56, "braces", "Schema Registry", "Confluent-compatible", opt=True)

# Dependencies
node(80, 680, 160, 56, "id", "Identity provider", "OIDC")
node(290, 680, 150, 56, "db", "PostgreSQL", "main database")
node(465, 680, 150, 56, "db", "PostgreSQL", "SQL database", opt=True)
node(640, 680, 150, 56, "bucket", "Object storage", "S3, GCS, Azure")

# Data path
edge([(240, 220), (338, 220)], "kafka")
label(269, 212, "SASL_SSL", "kafka")
edge([(580, 236), (878, 236)], "kafka")
label(710, 252, "SASL_SSL", "kafka", bg=GROUP_FILL)
edge([(580, 204), (850, 204), (850, 178), (878, 178)], "https")
label(710, 196, "encryption keys", "https", bg=GROUP_FILL)

# Management path
edge([(240, 410), (280, 410), (280, 236), (338, 236)], "https")
label(272, 322, "admin API", "https", anchor="end")
edge([(240, 444), (338, 444)], "https")
edge([(240, 478), (338, 478)], "https")
edge([(420, 432), (420, 250)], "kafka")
label(412, 340, "Kafka over TLS", "kafka", anchor="end", bg=GROUP_FILL)
edge([(500, 432), (500, 250)], "https")
label(508, 340, "admin API", "https", anchor="start", bg=GROUP_FILL)
edge([(580, 448), (878, 448)], "kafka")
label(710, 440, "SASL_SSL, direct", "kafka", bg=GROUP_FILL)
edge([(580, 472), (856, 472), (856, 652), (878, 652)], "https")
edge([(540, 490), (540, 548), (611, 548)], "metrics", both=True)

# Console and Cortex dependencies
w(f'<path d="M460,488 V632 M160,632 H540" fill="none" stroke="{HTTPS}" stroke-width="1.5"/>')
for x in (160, 365, 540):
    edge([(x, 632), (x, 678)], "https")
label(300, 628, "OIDC, PostgreSQL over TLS", "https")
edge([(715, 576), (715, 678)], "https")
label(715, 640, "S3 API", "https")

# Cluster prerequisites
w(f'<rect x="40" y="776" width="1120" height="56" rx="6" fill="{GROUP_FILL}" stroke="{LINE}"/>')
w('<text x="56" y="809" class="g">CLUSTER PREREQUISITES</text>')
for i, (ic, title, sub) in enumerate([
    ("globe", "Networking", "ingress, load balancer"),
    ("cert", "cert-manager", "TLS certificates"),
    ("lock", "Secret manager", "Vault, External Secrets"),
    ("pulse", "Monitoring", "Prometheus, Grafana"),
    ("logs", "Central logging", "JSON logs"),
]):
    x = 236 + i * 186
    icon(ic, x, 794, 20, MUTED)
    w(f'<text x="{x + 30}" y="801" class="t">{title}</text>')
    w(f'<text x="{x + 30}" y="817" class="s">{sub}</text>')

w("</g>")
w("</svg>")
sys.stdout.write("\n".join(out) + "\n")
