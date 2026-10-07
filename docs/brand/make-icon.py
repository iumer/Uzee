import sys
def svg(variant):
    if variant == "tinted":
        bg = '<rect width="1024" height="1024" fill="#000"/>'
        stroke = '#FFFFFF'; spark = '#FFFFFF'; glow = ''
        grad = ''
    else:
        base = "#0A0A1F" if variant == "light" else "#05050F"
        bg = f'''<rect width="1024" height="1024" fill="{base}"/>
<circle cx="260" cy="230" r="560" fill="url(#g1)"/>
<circle cx="860" cy="900" r="620" fill="url(#g2)"/>
<circle cx="900" cy="160" r="420" fill="url(#g3)"/>'''
        stroke = 'url(#u)'; spark = 'url(#s)'
        glow = '<use href="#mark" filter="url(#blur)" opacity="0.85"/>'
    grad = '''
<radialGradient id="g1"><stop offset="0" stop-color="#7C3AED" stop-opacity="0.75"/><stop offset="1" stop-color="#7C3AED" stop-opacity="0"/></radialGradient>
<radialGradient id="g2"><stop offset="0" stop-color="#2563EB" stop-opacity="0.7"/><stop offset="1" stop-color="#2563EB" stop-opacity="0"/></radialGradient>
<radialGradient id="g3"><stop offset="0" stop-color="#EC4899" stop-opacity="0.45"/><stop offset="1" stop-color="#EC4899" stop-opacity="0"/></radialGradient>
<linearGradient id="u" x1="300" y1="260" x2="740" y2="760" gradientUnits="userSpaceOnUse">
 <stop offset="0" stop-color="#22D3EE"/><stop offset="0.5" stop-color="#A78BFA"/><stop offset="1" stop-color="#F472B6"/></linearGradient>
<linearGradient id="s" x1="600" y1="150" x2="800" y2="400" gradientUnits="userSpaceOnUse">
 <stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#C4B5FD"/></linearGradient>
<filter id="blur" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="38"/></filter>'''
    def star(cx, cy, r):
        k = r * 0.16
        return (f'M{cx},{cy-r} C{cx+k},{cy-k} {cx+k},{cy-k} {cx+r},{cy} '
                f'C{cx+k},{cy+k} {cx+k},{cy+k} {cx},{cy+r} '
                f'C{cx-k},{cy+k} {cx-k},{cy+k} {cx-r},{cy} '
                f'C{cx-k},{cy-k} {cx-k},{cy-k} {cx},{cy-r} Z')
    mark = f'''<g id="mark">
<path d="M330,300 V560 A182,182 0 0 0 694,560 V455" fill="none" stroke="{stroke}" stroke-width="150" stroke-linecap="round"/>
<path d="{star(694,246,124)}" fill="{spark}"/>
<path d="{star(838,392,52)}" fill="{spark}" opacity="0.9"/>
</g>'''
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>{grad}{mark}</defs>{bg}{glow}<use href="#mark"/></svg>'''
for v in ["light","dark","tinted"]:
    open(f"icon-{v}.svg","w").write(svg(v))
