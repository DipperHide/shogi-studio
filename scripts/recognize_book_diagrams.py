"""Template-assisted transcription of the books' printed board characters.

The training locations below were visually checked against the supplied pages.
Predictions remain drafts. A high pixel-match score is not editorial approval.
"""
from pathlib import Path
import argparse
import json
import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SIZE = 40

def pixels(book, page):
    return np.asarray(Image.open(ROOT / "course_sources" / book / f"page-{page:03d}-0.jpg").convert("L"))

def cell_image(gray, diagram, row, col):
    xs, ys = diagram["x_lines"], diagram["y_lines"]
    x0,x1 = int(round(xs[col]))+3, int(round(xs[col+1]))-2
    y0,y1 = int(round(ys[row]))+3, int(round(ys[row+1]))-2
    return gray[y0:y1, x0:x1]

def normalize(gray):
    ink = np.uint8(gray < 120)
    if ink.sum() < max(7, ink.size*.008):
        return np.zeros((SIZE,SIZE),np.float32)
    ys,xs = np.nonzero(ink)
    ink = ink[ys.min():ys.max()+1,xs.min():xs.max()+1]
    # Preserve glyph proportions; uniformly scaled and centered in a fixed box.
    scale = (SIZE-4)/max(ink.shape)
    w,h = max(1,round(ink.shape[1]*scale)),max(1,round(ink.shape[0]*scale))
    resized = cv2.resize(ink.astype(np.float32),(w,h),interpolation=cv2.INTER_AREA)
    out = np.zeros((SIZE,SIZE),np.float32)
    y,x = (SIZE-h)//2,(SIZE-w)//2
    out[y:y+h,x:x+w] = resized
    return out

def training(reports):
    templates, names, provenance = [], [], []
    def add(book,page,index,row,col,value):
        d=reports[book]["pages"][page]["diagrams"][index]
        glyph=normalize(cell_image(pixels(book,page),d,row,col))
        for rotation in (0,2):
            rotated=np.rot90(glyph,rotation)
            for dy,dx in [(0,0),(-1,0),(1,0),(0,-1),(0,1)]:
                templates.append(np.roll(rotated,(dy,dx),axis=(0,1)).flatten())
                names.append(value if rotation==0 else -value)
        provenance.append({"book":book,"page":page,"diagram":index,"row":row,"column":col,"piece":value})
    back=[2,3,4,5,8,5,4,3,2]
    standard=[-v for v in back]+[0,-7,0,0,0,0,0,-6,0]+[-1]*9+[0]*27+[1]*9+[0,6,0,0,0,0,0,7,0]+back
    for i,value in enumerate(standard):
        if value: add("hanyu-intro",16,0,i//9,i%9,value)
    opening=[-2,-3,0,-5,-8,-5,-4,-3,-2,0,-7,0,-4,0,0,0,-6,0,-1,0,-1,-1,-1,-1,0,-1,-1,0,-1,0,0,0,0,-1,0,0]+[0]*9+[0,0,1,0,0,0,0,0,0]+[1,1,4,1,1,1,1,1,1]+[0,6,0,0,0,0,0,7,0]+[2,3,0,5,8,5,4,3,2]
    assert len(standard)==81 and len(opening)==81
    for i,value in enumerate(opening):
        if value: add("hanyu-opening",15,0,i//9,i%9,value)
    for page,kind in [(26,9),(30,10),(34,11),(38,12)]:
        for row,col in [(0,8),(3,4),(4,8),(8,4)]: add("hanyu-intro",page,0,row,col,kind)
    for page,kind in [(46,14),(50,15)]: add("hanyu-intro",page,0,4,4,kind)
    for row,col in [(0,7),(1,8),(2,3),(2,4),(2,5),(3,3),(3,5),(3,7),(3,8),(4,4),(4,7),(5,8),(7,3),(7,4),(7,5),(8,3),(8,5),(0,6),(1,4),(2,7),(6,4)]:
        add("hanyu-intro",26,0,row,col,0)
    return np.asarray(templates),np.asarray(names),provenance

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--limit",type=int,default=0)
    args=parser.parse_args()
    reports={book:json.loads((ROOT/"course_sources"/book/"diagrams.json").read_text(encoding="utf-8")) for book in ["hanyu-intro","hanyu-opening"]}
    templates,names,provenance=training(reports)
    template_norms=(templates*templates).sum(axis=1)
    kinds=sorted(set(int(n) for n in names))
    (ROOT/"course_sources/glyph-training.json").write_text(json.dumps(provenance,ensure_ascii=False,indent=2),encoding="utf-8")
    for book,report in reports.items():
        recognized={"book":book,"reviewed":False,"pages":[]}
        totals={"cells":0,"occupied_predictions":0,"uncertain_cells":0}
        for page in report["pages"][:args.limit or None]:
            gray=pixels(book,page["page"])
            diagrams=[]
            for d in page["diagrams"]:
                cells=[]
                patches=[]
                for row in range(d["rows"]):
                    for col in range(d["columns"]):
                        patches.append(normalize(cell_image(gray,d,row,col)).flatten())
                patches=np.asarray(patches)
                norms=(patches*patches).sum(axis=1)
                scores=2*(patches@templates.T)/(norms[:,None]+template_norms[None,:]+1e-6)
                by_kind=np.stack([scores[:,names==kind].max(axis=1) for kind in kinds],axis=1)
                for i in range(len(patches)):
                    totals["cells"]+=1
                    if norms[i]<1:
                        cells.append({"piece":0,"score":1.0,"margin":1.0,"empty":True})
                        continue
                    order=np.argsort(by_kind[i])[::-1]
                    score=float(by_kind[i,order[0]])
                    margin=float(score-by_kind[i,order[1]])
                    value=kinds[order[0]]
                    uncertain=score<.72 or margin<.07
                    cells.append({"piece":value,"score":round(score,4),"margin":round(margin,4),"annotation":value==0,"uncertain":uncertain})
                    totals["occupied_predictions"]+=value!=0
                    totals["uncertain_cells"]+=uncertain
                diagrams.append({**d,"cells":cells,"review_status":"unreviewed","uncertain_cells":sum(c.get("uncertain",False) for c in cells)})
            recognized["pages"].append({"page":page["page"],"diagrams":diagrams})
            if page["page"]%25==0: print(book,page["page"],flush=True)
        recognized["totals"]=totals
        (ROOT/"course_sources"/book/"recognized-diagrams.json").write_text(json.dumps(recognized,ensure_ascii=False,indent=2),encoding="utf-8")
        print(json.dumps({"book":book,**totals,"reviewed":False}),flush=True)

if __name__=="__main__":
    main()
