"""Generate original Quiet + Warm vector brand masters and editable Canva pages.
Requires fonttools (build tooling only). Raster exports use render_quiet_warm.cjs.
"""
from pathlib import Path
import json, html
import xml.etree.ElementTree as ET
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/brand/quiet-warm'
OUT.mkdir(parents=True,exist_ok=True)
font=TTFont(ROOT/'assets/fonts/Manrope-Variable.ttf')
glyphs=font.getGlyphSet(location={'wght':650})
cmap=font.getBestCmap(); upm=font['head'].unitsPerEm
C={'cream':'#F5EDD9','paper':'#FBF7ED','blue':'#91B4C8','powder':'#C3D7E4','ink':'#443C32','yellow':'#F0D18B','dark':'#24231F','selected':'#286280'}
manifest=[]
def paths(text,size,x,y,color):
 scale=size/upm; chunks=[]; cursor=x
 for ch in text:
  g=glyphs[cmap[ord(ch)]]; pen=SVGPathPen(glyphs)
  g.draw(TransformPen(pen,(scale,0,0,-scale,cursor,y)))
  chunks.append(f'<path fill="{color}" d="{pen.getCommands()}"/>')
  cursor+=g.width*scale
 return ''.join(chunks),cursor-x
def text_width(t,s): return sum(glyphs[cmap[ord(ch)]].width for ch in t)*s/upm
def wordmark(width=1200,color=C['ink']):
 size=width/text_width('workloop',1); p,_=paths('workloop',size,0,size*.81,color)
 return p,round(size*1.05)
def symbol(x=0,y=0,size=512,mono=None):
 # Original small-business window: a lowercase w, quiet title strip, and fine outline.
 ink=mono or C['ink']; paper='none' if mono else C['cream']; bar='none' if mono else C['blue']
 w=512; h=448; p=f'<g transform="translate({x} {y}) scale({size/512})">'
 p+=f'<rect x="9" y="9" width="494" height="430" rx="40" fill="{paper}" stroke="{ink}" stroke-width="16"/>'
 if not mono:p+=f'<path d="M49 17H463Q495 17 495 49V106H17V49Q17 17 49 17Z" fill="{bar}"/>'
 p+=f'<path d="M17 108H495" fill="none" stroke="{ink}" stroke-width="12"/>'
 p+=f'<path d="M53 63H126" stroke="{ink}" stroke-width="12" stroke-linecap="round"/>'
 sizefont=360; width=text_width('w',sizefont)
 p+=paths('w',sizefont,(512-width)/2,361,ink)[0]
 return p+'</g>'
def svg(w,h,body,bg=None):
 return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" aria-label="Workloop">'+(f'<rect width="{w}" height="{h}" fill="{bg}"/>' if bg else '')+body+'</svg>'
def save(name,w,h,body,bg=None,usage=''):
 (OUT/(name+'.svg')).write_text(svg(w,h,body,bg)); manifest.append({'name':name,'width':w,'height':h,'usage':usage,'source':name+'.svg'})
for name,color in [('ink',C['ink']),('cream',C['cream']),('black','#000000'),('white','#FFFFFF')]:
 p,h=wordmark(1200,color);save('wordmark-'+name,1200,h,p,usage='Transparent wordmark; vector lettering prevents font substitution.')
 save('symbol-'+name,512,448,symbol(mono=color),usage='Single-colour compact mark.')
save('symbol-colour',512,448,symbol(),usage='Transparent original compact mark.')
for name,bg in [('cream',C['cream']),('blue',C['powder']),('dark',C['dark'])]:
 save('app-icon-'+name,1024,1024,symbol(184,224,656),bg,'Opaque square app/store icon. OS supplies the outer mask.')
 save('avatar-'+name,1080,1080,symbol(260,298,560),bg,'Circle-safe social avatar.')
for name,color in [('ink',C['ink']),('cream',C['cream'])]:
 p,h=wordmark(1000,color)
 save('lockup-horizontal-'+name,1400,350,symbol(0,45,290,mono=color)+f'<g transform="translate(360 85)">{p}</g>',usage='Horizontal logo with original window mark.')
 p,h=wordmark(900,color)
 save('lockup-stacked-'+name,1080,1080,symbol(290,130,500,mono=color)+f'<g transform="translate(90 690)">{p}</g>',usage='Stacked mark and wordmark.')
# Splash image is transparent and remains legible when Android/iOS choose the background.
p,h=wordmark(670);save('splash-lockup',840,840,symbol(245,138,350)+f'<g transform="translate(85 520)">{p}</g>',usage='Native centred splash lockup, transparent.')
p,h=wordmark(670,C['cream']);save('splash-lockup-dark',840,840,symbol(245,138,350)+f'<g transform="translate(85 520)">{p}</g>',usage='Dark native splash: same colour mark, cream lettering, transparent.')
# A dedicated adaptive monochrome layer. The centred 48dp-wide mark fits
# inside the 66dp safe region of a 108dp layer; never reuse the 24dp status icon.
save('android-adaptive-monochrome',1080,1080,symbol(300,330,480,mono='#FFFFFF'),usage='Single white alpha mask, 108dp adaptive canvas; OS supplies themed colour.')
mono_root=ET.fromstring(svg(512,448,symbol(mono='#FFFFFF')))
mono_paths=[]
for node in mono_root[0]:
 attrs=node.attrib
 if node.tag.endswith('rect'):
  d='M49 9H463Q503 9 503 49V399Q503 439 463 439H49Q9 439 9 399V49Q9 9 49 9Z'
 else:
  d=attrs['d']
 fields={'android:pathData':d,'android:fillColor': '#FFFFFFFF' if attrs.get('fill')=='#FFFFFF' else '#00000000'}
 if 'stroke' in attrs:
  fields.update({'android:strokeColor':'#FFFFFFFF','android:strokeWidth':attrs['stroke-width']})
 if 'stroke-linecap' in attrs: fields['android:strokeLineCap']=attrs['stroke-linecap']
 mono_paths.append('    <path '+' '.join(f'{k}="{html.escape(v,quote=True)}"' for k,v in fields.items())+' />')
mono_xml='<?xml version="1.0" encoding="utf-8"?>\n<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">\n  <group android:translateX="30" android:translateY="33" android:scaleX="0.09375" android:scaleY="0.09375">\n'+'\n'.join(mono_paths)+'\n  </group>\n</vector>\n'
(OUT/'android-adaptive-monochrome.xml').write_text(mono_xml)

# Actual platform deliverable canvases: text is reusable marketing copy, not fabricated usage data.
def social(name,w,h,heading,sub,safe=False):
 markw=min(w*.53,850); p,ph=wordmark(markw)
 cx=w/2; cy=h/2
 body=f'<rect x="{w*.08}" y="{h*.12}" width="{w*.84}" height="{h*.76}" rx="{min(w,h)*.025}" fill="{C["cream"]}" stroke="{C["ink"]}" stroke-width="2"/>'
 body+=f'<g transform="translate({cx-markw/2} {cy-ph*.8})">{p}</g>'
 size=min(w*.055,76); tw=text_width(heading,size)
 body+=paths(heading,size,cx-tw/2,cy+ph*.53,C['ink'])[0]
 size2=min(w*.024,32); tw2=text_width(sub,size2)
 body+=paths(sub,size2,cx-tw2/2,cy+ph*.9+size2,C['selected'])[0]
 save(name,w,h,body,C['powder'],'Branded export; safe central content. Review platform crop on upload.')
social('social-square',1080,1080,'Your business, in order.','Client · Booking · Work · Payment · Repeat')
social('social-portrait',1080,1350,'Your business, in order.','Client · Booking · Work · Payment · Repeat')
social('social-story',1080,1920,'Your business, in order.','workloop.uk')
social('social-preview',1200,630,'Your business, in order.','workloop.uk')
social('social-banner',1500,500,'Your business, in order.','workloop.uk')
social('facebook-cover',1640,924,'Your business, in order.','workloop.uk')
social('youtube-banner',2560,1440,'Your business, in order.','workloop.uk')
# Editable Canva source: independent page elements, real editable text, SVG symbol.
font64=__import__('base64').b64encode((ROOT/'assets/fonts/Manrope-Variable.ttf').read_bytes()).decode()
css=f'''@font-face{{font-family:Manrope;src:url(data:font/ttf;base64,{font64})}}*{{box-sizing:border-box}}body{{margin:0;background:white;font-family:Manrope,sans-serif;color:{C['ink']}}}.page{{position:relative;width:1080px;height:1080px;padding:70px;overflow:hidden;background:{C['cream']};page-break-after:always}}.label{{font:20px monospace;letter-spacing:3px}}.logo{{font-size:146px;font-weight:650;letter-spacing:-5px}}.center{{position:absolute;left:70px;right:70px;top:350px;text-align:center}}.foot{{position:absolute;bottom:65px;font-size:20px}}'''
pages=[]
def page(title,body,bg=None,colour=None):
 style=f'background:{bg or C["cream"]};color:{colour or C["ink"]}'
 pages.append(f'<section class="page" data-document-role="page" data-label="{html.escape(title)}" style="{style}"><div class="label">WORKLOOP / {html.escape(title.upper())}</div>{body}<div class="foot">Quiet + Warm · Brand master</div></section>')
page('Primary wordmark','<div class="center logo">workloop</div>')
page('Reversed wordmark','<div class="center logo">workloop</div>',C['dark'],C['cream'])
page('Compact mark','<div style="position:absolute;left:280px;top:300px">'+svg(520,455,symbol(size=520))+'</div>')
page('App icon','<div style="position:absolute;left:270px;top:250px">'+svg(540,540,symbol(98,119,346),C['powder'])+'</div>')
page('Horizontal logo','<div style="position:absolute;left:100px;top:395px">'+svg(220,200,symbol(size=220))+'</div><div class="logo" style="position:absolute;left:355px;top:415px;font-size:105px">workloop</div>')
page('Stacked logo','<div style="position:absolute;left:365px;top:250px">'+svg(350,310,symbol(size=350))+'</div><div class="center logo" style="top:620px;font-size:135px">workloop</div>')
page('Colour palette','<div style="display:flex;flex-wrap:wrap;gap:30px;margin-top:110px">'+''.join(f'<div style="width:285px"><div style="height:180px;border:2px solid {C["ink"]};border-radius:8px;background:{val}"></div><h2 style="font-size:28px">{key.title()}</h2><p style="font-size:24px">{val}</p></div>' for key,val in list(C.items())[:6])+'</div>')
page('Typography','<div style="margin-top:150px"><h1 style="font-size:74px">Your business, in order.</h1><p style="font-size:34px;line-height:1.6">Manrope for clear, friendly reading.<br>IBM Plex Mono for small labels and dates.</p><div style="padding:40px;border:2px solid #443C32;background:#91B4C8;font:24px monospace">CLIENT → BOOKING → WORK → PAYMENT → REPEAT</div></div>')
(OUT/'canva-brand-masters.html').write_text('<!doctype html><html><head><meta charset="utf-8"><style>'+css+'</style></head><body>'+''.join(pages)+'</body></html>')
(OUT/'manifest.json').write_text(json.dumps({'palette':C,'masters':manifest,'canva_pages':8,'font':'Manrope 650, SIL OFL; outlined SVG letters','symbol':'Original lowercase w inside a small business window'},indent=2))
print('Generated',len(manifest),'vector masters and eight-page editable Canva source in',OUT)
