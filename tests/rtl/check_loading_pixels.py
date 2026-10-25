#!/usr/bin/env python3
"""Validate captured RTL output against the bitmap and visible UI contract."""
from pathlib import Path
import hashlib,json
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
HERE=ROOT/'build/loading-tests'
art=[int(v,16) for v in (ROOT/'src/rtl/openice_loading.hex').read_text().split()]
assert len(art)==180*114 and max(art)<32
expected_art=bytes(((v<<3)|(v>>2)) for v in art)
checks=[]
for name,p,fault in [('000',0,False),('001',1,False),('009',9,False),('010',10,False),('042',42,False),('099',99,False),('100',100,False),('clamp',100,False),('fault',42,True),('reset',0,False)]:
    path=HERE/f'loading-{name}.ppm'
    im=Image.open(path).convert('RGB')
    assert im.size==(400,254)
    pixels=im.load()
    for y in range(228):
        for x in range(400):
            level=expected_art[(y//2)*180+(x-20)//2] if 20<=x<380 else 0
            assert pixels[x,y]==(level,)*3,(name,x,y,pixels[x,y],level)
    # Exact bar support, dimensions and fill. Border is separated by a black
    # pixel from the area which represents 100 integral percentage points.
    for y in range(246,254):
        for x in range(400):
            border=48<=x<=351 and (x in (48,351) or y in (246,253))
            fill=50<=x<50+3*p and 248<=y<=251
            expected=(104,116,128) if border else ((200,56,56) if fault else (64,200,232)) if fill else (0,0,0)
            assert pixels[x,y]==expected,(name,x,y,pixels[x,y],expected)
    im.save(HERE/f'loading-{name}.png')
    checks.append({'frame':name,'percent':p,'fault':fault,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
# Clamp and resetting reproduce the corresponding canonical complete frames.
assert Image.open(HERE/'loading-100.ppm').tobytes()==Image.open(HERE/'loading-clamp.ppm').tobytes()
assert Image.open(HERE/'loading-000.ppm').tobytes()==Image.open(HERE/'loading-reset.ppm').tobytes()
# OCR the numeric region at 2x font scale, independently checking each numeral
# rather than assuming a changed colored bar also means a changed label.
expected_digits={
    '0':['01110','10001','10011','10101','11001','10001','01110'],
    '1':['00100','01100','00100','00100','00100','00100','01110'],
    '2':['01110','10001','00001','00010','00100','01000','11111'],
    '4':['00010','00110','01010','10010','11111','00010','00010'],
    '9':['01110','10001','10001','01111','00001','00001','01110'],
    ' ':['00000']*7,
}
for name,p in [('000',0),('001',1),('009',9),('010',10),('042',42),('099',99),('100',100)]:
    px=Image.open(HERE/f'loading-{name}.ppm').load()
    for n,char in enumerate(f'{p:3d}'):
        for y in range(7):
            row=''.join('1' if px[224+n*12+x*2,230+y*2]==(240,244,248) else '0' for x in range(5))
            assert row==expected_digits[char][y],(name,char,y,row)
report={'result':'PASS','cases':checks,'checks':['independent raster period and pulse widths (SV)','frame-coherent percent/fault update (SV)','complete artwork pixel alignment','percentage bar bounds and pixel-exact fill','numeric label OCR','100% clamp','fault palette','reset equivalence']}
(HERE/'result.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
