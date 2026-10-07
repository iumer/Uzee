"""UZee app icon: "Wallet pal", a smiling wallet with two cards. Writes icon-light/dark/tinted.svg (1024 x 1024)."""

def svg(v):
    tinted = v == "tinted"
    dark = v == "dark"
    if tinted:
        bg = '<rect width="1024" height="1024" fill="#000"/>'
        card1, card2 = "#8A8A8A", "#B8B8B8"
        body, ink, clasp, button = "#FFFFFF", "#000000", "#D9D9D9", "#000000"
        cheek_op = 0
    else:
        top, bottom = ("#43E3A6", "#0B9467") if not dark else ("#0F3D2E", "#04140F")
        bg = f'''<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient>
<radialGradient id="sheen" cx="0.22" cy="0.12" r="0.75"><stop offset="0" stop-color="#FFFFFF" stop-opacity="{0.32 if not dark else 0.10}"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>
<radialGradient id="glow" cx="0.5" cy="0.62" r="0.5"><stop offset="0" stop-color="#34D399" stop-opacity="{0.0 if not dark else 0.35}"/><stop offset="1" stop-color="#34D399" stop-opacity="0"/></radialGradient>
<rect width="1024" height="1024" fill="url(#bg)"/><rect width="1024" height="1024" fill="url(#sheen)"/><rect width="1024" height="1024" fill="url(#glow)"/>'''
        card1, card2 = "url(#c1)", "url(#c2)"
        body, ink, clasp, button = "url(#body)", "#0A4D38", "url(#clasp)", "url(#btn)"
        cheek_op = 0.55
    defs = f'''
<linearGradient id="c1" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FDE68A"/><stop offset="0.45" stop-color="#FBBF24"/><stop offset="1" stop-color="#F59E0B"/></linearGradient>
<linearGradient id="c2" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#93C5FD"/><stop offset="0.5" stop-color="#60A5FA"/><stop offset="1" stop-color="#3B82F6"/></linearGradient>
<linearGradient id="body" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="{'#E3F6EE' if not dark else '#CFE9DF'}"/></linearGradient>
<linearGradient id="clasp" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#E7FBF2"/><stop offset="1" stop-color="#BDEFD9"/></linearGradient>
<radialGradient id="btn" cx="0.35" cy="0.3" r="0.8"><stop offset="0" stop-color="#34D399"/><stop offset="1" stop-color="#047857"/></radialGradient>
<filter id="drop" x="-30%" y="-30%" width="160%" height="170%"><feDropShadow dx="0" dy="28" stdDeviation="30" flood-color="#053B2A" flood-opacity="{0.38 if not tinted else 0}"/></filter>
<filter id="soft" x="-30%" y="-30%" width="160%" height="170%"><feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#053B2A" flood-opacity="{0.25 if not tinted else 0}"/></filter>
<filter id="ground" x="-50%" y="-300%" width="200%" height="700%"><feGaussianBlur stdDeviation="18"/></filter>
<clipPath id="bodyClip"><rect x="200" y="368" width="624" height="440" rx="104"/></clipPath>'''
    def card(x, y, rot, fill, cx, cy):
        stripe = "" if tinted else f'<rect x="{x}" y="{y+62}" width="400" height="44" fill="#000" opacity="0.10"/>'
        chip = "" if tinted else f'<rect x="{x+44}" y="{y+132}" width="70" height="52" rx="12" fill="#FFF7D6" opacity="0.85"/>'
        shine = "" if tinted else f'<rect x="{x+2}" y="{y+2}" width="396" height="246" rx="38" fill="none" stroke="#FFFFFF" stroke-opacity="0.45" stroke-width="4"/>'
        return (f'<g transform="rotate({rot} {cx} {cy})" filter="url(#soft)"><rect x="{x}" y="{y}" width="400" height="250" rx="40" fill="{fill}"/>'
                f'{stripe}{chip}{shine}</g>')
    stitch = "" if tinted else '<rect x="236" y="404" width="552" height="368" rx="76" fill="none" stroke="#A7E3CB" stroke-width="7" stroke-dasharray="2 22" stroke-linecap="round" opacity="0.9"/>'
    highlight = "" if tinted else '<rect x="203" y="371" width="618" height="434" rx="101" fill="none" stroke="#FFFFFF" stroke-width="6" opacity="0.9"/>'
    cheeks = "" if tinted else f'<ellipse cx="338" cy="612" rx="34" ry="20" fill="#6EE7B7" opacity="{cheek_op}"/><ellipse cx="582" cy="612" rx="34" ry="20" fill="#6EE7B7" opacity="{cheek_op}"/>'
    catch = "" if tinted else '<circle cx="408" cy="526" r="12" fill="#FFFFFF" opacity="0.9"/><circle cx="526" cy="526" r="12" fill="#FFFFFF" opacity="0.9"/>'
    btn_hl = "" if tinted else '<circle cx="707" cy="580" r="9" fill="#FFFFFF" opacity="0.7"/>'
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>{defs}</defs>
{bg}
{card(282, 214, -10, card1, 482, 339)}
{card(352, 236, 6, card2, 552, 361)}
<ellipse cx="512" cy="822" rx="250" ry="20" fill="#053B2A" filter="url(#ground)" opacity="{0.22 if not tinted else 0}"/>
<g filter="url(#drop)"><rect x="200" y="368" width="624" height="440" rx="104" fill="{body}"/></g>
{highlight}{stitch}
<g filter="url(#soft)"><rect x="640" y="524" width="222" height="136" rx="68" fill="{clasp}"/></g>
<circle cx="712" cy="592" r="30" fill="{button}"/>{btn_hl}
{cheeks}
<circle cx="398" cy="540" r="40" fill="{ink}"/><circle cx="516" cy="540" r="40" fill="{ink}"/>{catch}
<path d="M372,644 Q457,722 542,644" stroke="{ink}" stroke-width="40" fill="none" stroke-linecap="round"/>
</svg>'''

for v in ["light", "dark", "tinted"]:
    open(f"icon-{v}.svg", "w").write(svg(v))
