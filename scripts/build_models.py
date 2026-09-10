"""Deterministic, original low-poly shogi assets. Python + Pillow + NumPy.
Coordinates: +Y up, +Z toward sente. One scene unit = 40 mm.
All material images are embedded in the exported glTF 2.0 binaries.
"""
from pathlib import Path
import io, json, math, struct, copy
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from build_piece_faces import piece_atlas, boxwood
from photo_wood import wood, material as photo_material, board_side_atlas

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'models'
TEX = ROOT / 'assets/textures'
FONT = ROOT / 'assets/fonts/YujiSyuku-Regular.ttf'
LAYOUT = json.loads((ROOT/'godot/assets/scene-layout.json').read_text())
OUT.mkdir(exist_ok=True); TEX.mkdir(parents=True, exist_ok=True)

board_w,board_h=1792,2048
board=photo_material('kaya-long-grain.png',(board_w,board_h),(183,145,88),0.62)
d=ImageDraw.Draw(board)
for k in range(10):
    x=(.5+(-4.41+k*.98)/9.6)*board_w;y=(.5+(-4.86+k*1.08)/10.6)*board_h
    # A fine lit lip beside the dark incised line, below one screen pixel.
    d.line([(x+2,(.5-4.86/10.6)*board_h),(x+2,(.5+4.86/10.6)*board_h)],fill=(198,161,106),width=1)
    d.line([((.5-4.41/9.6)*board_w,y+2),((.5+4.41/9.6)*board_w,y+2)],fill=(198,161,106),width=1)
    d.line([(x,(.5-4.86/10.6)*board_h),(x,(.5+4.86/10.6)*board_h)],fill=(36,25,13),width=3)
    d.line([((.5-4.41/9.6)*board_w,y),((.5+4.41/9.6)*board_w,y)],fill=(36,25,13),width=3)
for i in [3,6]:
    for j in [3,6]:
        x=(.5+(-4.41+i*.98)/9.6)*board_w;y=(.5+(-4.86+j*1.08)/10.6)*board_h
        d.ellipse((x-4.5,y-4.5,x+4.5,y+4.5),fill=(39,31,20))
side=board_side_atlas()
tray=wood(768,768,(128,93,52),29,1.05)
edge=boxwood(ROOT,3,(1024,256))
labels=['王将','玉将','飛車','角行','金将','銀将','桂馬','香車','歩兵','龍王','龍馬','成銀','成桂','成香','と','']
atlas,ink_mask=piece_atlas(ROOT,FONT,wood)
ink_mask.save(ROOT/'godot/assets/materials/piece-ink.png')

y,x=np.mgrid[0:512,0:512]
weave=3*np.sin(x*math.tau/7)+2*np.sin(y*math.tau/4)+3.5*np.sin(y*math.tau/43)
weave+=1.1*np.cos(x*math.tau/14+y*math.tau/8)
tatami=Image.fromarray(np.clip(np.array([130,137,88])+weave[:,:,None],0,255).astype('uint8'))
images={'board':board,'side':side,'tray':tray,'pieces':atlas,'tatami':tatami,'piece-edge':edge}
for name,im in images.items(): im.save(TEX/(name+'.jpg'),quality=96,subsampling=0)
for name in ['pieces','piece-edge']:
    images[name].save(TEX/(name+'.png'),optimize=True)

class GLB:
    def __init__(self):
        self.doc={'asset':{'version':'2.0','generator':'Shogi classic material revision 0.4.2','copyright':'Original geometry and reference-guided generated wood; embedded Ryoko glyph artwork by LuffyKudo, CC-BY-SA-4.0; see assets/calligraphy/ryoko/provenance.json'},'scene':0,'scenes':[{'name':'Shogi art review','nodes':[]}],'nodes':[],'meshes':[],'materials':[],'textures':[],'images':[],'samplers':[{'magFilter':9729,'minFilter':9987,'wrapS':10497,'wrapT':10497}],'accessors':[],'bufferViews':[],'buffers':[{'byteLength':0}]}
        self.buf=bytearray(); self.materials={}
    def blob(self,data,target=None):
        while len(self.buf)%4: self.buf+=b'\x00'
        view={'buffer':0,'byteOffset':len(self.buf),'byteLength':len(data)}
        if target: view['target']=target
        self.buf+=data; self.doc['bufferViews'].append(view)
        return len(self.doc['bufferViews'])-1
    def accessor(self,data,typ):
        a=np.asarray(data,dtype='<f4')
        idx=self.blob(a.tobytes(),34962)
        item={'bufferView':idx,'componentType':5126,'count':len(a),'type':typ}
        if typ=='VEC3': item.update(min=a.min(axis=0).tolist(),max=a.max(axis=0).tolist())
        self.doc['accessors'].append(item); return len(self.doc['accessors'])-1
    def material(self,name,img=None,color=None,rough=.6):
        if name in self.materials:return self.materials[name]
        pbr={'metallicFactor':0,'roughnessFactor':rough}
        if img:
            lossless = img in ['pieces','piece-edge']
            extension = '.png' if lossless else '.jpg'
            self.doc['images'].append({'name':name,'bufferView':self.blob((TEX/(img+extension)).read_bytes()),'mimeType':'image/png' if lossless else 'image/jpeg'})
            self.doc['textures'].append({'sampler':0,'source':len(self.doc['images'])-1})
            pbr['baseColorTexture']={'index':len(self.doc['textures'])-1}
        if color:pbr['baseColorFactor']=color
        self.doc['materials'].append({'name':name,'pbrMetallicRoughness':pbr})
        self.materials[name]=len(self.doc['materials'])-1
        return self.materials[name]
    def mesh(self,name,groups,smooth=False):
        primitives=[]
        for mat,triangles in groups.items():
            pp=[]; nn=[]; uv=[]
            for verts,coords in triangles:
                a=np.asarray(verts); normal=np.cross(a[1]-a[0],a[2]-a[0]); normal=normal/np.linalg.norm(normal)
                pp.extend(verts); nn.extend([normal.tolist()]*3); uv.extend(coords)
            if smooth:
                sums={}
                for p,n in zip(pp,nn):
                    key=tuple(round(v,6) for v in p);sums[key]=sums.get(key,np.zeros(3))+np.array(n)
                nn=[(sums[tuple(round(v,6) for v in p)]/np.linalg.norm(sums[tuple(round(v,6) for v in p)])).tolist() for p in pp]
            primitives.append({'attributes':{'POSITION':self.accessor(pp,'VEC3'),'NORMAL':self.accessor(nn,'VEC3'),'TEXCOORD_0':self.accessor(uv,'VEC2')},'material':mat})
        self.doc['meshes'].append({'name':name,'primitives':primitives})
        return len(self.doc['meshes'])-1
    def node(self,name,mesh=None,pos=(0,0,0),rot=None,scale=None,children=None,extras=None,root=True):
        n={'name':name,'translation':list(pos)}
        if mesh is not None:n['mesh']=mesh
        if rot is not None:n['rotation']=list(rot)
        if scale:n['scale']=list(scale)
        if children:n['children']=children
        if extras:n['extras']=extras
        idx=len(self.doc['nodes']); self.doc['nodes'].append(n)
        if root:self.doc['scenes'][0]['nodes'].append(idx)
        return idx
    def save(self,path):
        self.doc['buffers'][0]['byteLength']=len(self.buf)
        data=json.dumps(self.doc,separators=(',',':'),ensure_ascii=False).encode('utf8')
        data+=b' '*((-len(data))%4); buf=bytes(self.buf)+b'\x00'*((-len(self.buf))%4)
        glb=struct.pack('<III',0x46546c67,2,12+8+len(data)+8+len(buf))+struct.pack('<II',len(data),0x4e4f534a)+data+struct.pack('<II',len(buf),0x004e4942)+buf
        path.write_bytes(glb)

def addtri(groups,mat,verts,uv): groups.setdefault(mat,[]).append((verts,uv))

def prism(g,name,outline,height,topmat,sidemat,bottommat=None,bevel=.035,slope=0,atlas_top=None,atlas_bottom=None):
    """Closed chamfered convex prism, flat split normals, all faces outward."""
    groups={}; bottommat=sidemat if bottommat is None else bottommat
    width=max(p[0] for p in outline)-min(p[0] for p in outline)
    depth=max(p[1] for p in outline)-min(p[1] for p in outline)
    inset=1-bevel/min(width,depth)*2
    rings=[]
    for scale,kind in [(inset,0),(1,1),(1,2),(inset,3)]:
        ring=[]
        for x,z in outline:
            xx,zz=x*scale,z*scale
            yy=[0,bevel,height+slope*zz-bevel,height+slope*zz][kind]
            ring.append([xx,yy,zz])
        rings.append(ring)
    def uv(v,tile=None,bottom=False):
        u=.5+v[0]/width; v=.5+v[2]/depth
        if bottom:u=1-u
        if tile is not None:return [(tile%4+u)/4,(tile//4+v)/4]
        return [u,v]
    n=len(outline)
    for i in range(n):
        j=(i+1)%n
        verts=[[0,height,0],rings[-1][i],rings[-1][j]]
        addtri(groups,topmat,verts,[uv(v,atlas_top) for v in verts])
        verts=[[0,0,0],rings[0][j],rings[0][i]]
        addtri(groups,bottommat,verts,[uv(v,atlas_bottom,True) for v in verts])
        for r in range(3):
            a,b,c,d=rings[r][i],rings[r][j],rings[r+1][j],rings[r+1][i]
            coords=lambda v, u: [u,1-v[1]/height]
            addtri(groups,sidemat,[a,b,c],[coords(a,i/n),coords(b,(i+1)/n),coords(c,(i+1)/n)])
            addtri(groups,sidemat,[a,c,d],[coords(a,i/n),coords(c,(i+1)/n),coords(d,i/n)])
    return g.mesh(name,groups)

def box(g,name,w,d,h,top,side,bevel=.035):
    return prism(g,name,[(-w/2,d/2),(w/2,d/2),(w/2,-d/2),(-w/2,-d/2)],h,top,side,bevel=bevel)

specs=[('king',0,None,.88,1.01,.23),('jewel',1,None,.88,1.01,.23),('rook',2,9,.84,.98,.215),('bishop',3,10,.82,.96,.21),('gold',4,None,.8,.94,.20),('silver',5,11,.78,.92,.19),('knight',6,12,.74,.90,.18),('lance',7,13,.71,.88,.17),('pawn',8,14,.68,.84,.16)]

def materials(g):
    return {'board':g.material('Honey kaya / gridded top','board',rough=.52),
            'side':g.material('Kaya edge grain','side',rough=.55),
            'tray':g.material('Dark walnut','tray',rough=.55),
            'pieces':g.material('Boxwood and Ryoko calligraphy CC-BY-SA-4.0','pieces',rough=.46),
            'piece_edge':g.material('Boxwood end grain bevel','piece-edge',rough=.48),
            'tatami':g.material('Woven rush tatami','tatami',rough=.96),
            'border':g.material('Tatami dark cloth border',color=[.12,.16,.10,1],rough=.95)}

def piece_mesh(g,m,spec):
    name,front,back,w,d,h=spec
    corners=np.array([(-w/2,d/2),(w/2,d/2),(.43*w,-.30*d),(0,-d/2),(-.43*w,-.30*d)])
    outline=[]
    # Tiny plan-view rounding removes razor corners without changing the
    # recognisable five-sided silhouette or the existing hit/animation bounds.
    for i,p in enumerate(corners):
        a,b=corners[(i-1)%5]-p,corners[(i+1)%5]-p
        a=p+a/np.linalg.norm(a)*.009;b=p+b/np.linalg.norm(b)*.009
        for t in [0,.5,1]:
            outline.append((1-t)**2*a+2*(1-t)*t*p+t*t*b)
    bevel=.009
    rings=[]
    for top in [False,True]:
        for angle in ([0,30,60,90] if not top else [90,60,30,0]):
            radians=math.radians(angle)
            scale=1-2*bevel/min(w,d)*(1-math.sin(radians))
            lip=bevel*(1-math.cos(radians))
            rings.append([[x*scale,h+.052*z*scale-lip if top else lip,z*scale] for x,z in outline])
    groups={};n=len(outline)
    reverse=15 if back is None else back
    def face_uv(v,tile,bottom=False):
        u=.5+v[0]/w;vv=.5+v[2]/d
        if bottom:u=1-u
        return [(tile%4+u)/4,(tile//4+vv)/4]
    lengths=[np.linalg.norm(outline[(i+1)%n]-outline[i]) for i in range(n)]
    offsets=np.concatenate(([0],np.cumsum(lengths)))/sum(lengths)
    for i in range(n):
        j=(i+1)%n
        vs=[[0,h,0],rings[-1][i],rings[-1][j]]
        addtri(groups,m['pieces'],vs,[face_uv(v,front) for v in vs])
        vs=[[0,0,0],rings[0][j],rings[0][i]]
        addtri(groups,m['pieces'],vs,[face_uv(v,reverse,True) for v in vs])
        for r in range(len(rings)-1):
            a,b,c,e=rings[r][i],rings[r][j],rings[r+1][j],rings[r+1][i]
            if r==3:
                uv=lambda v,u:[u,1-v[1]/h]
                addtri(groups,m['piece_edge'],[a,b,c],[uv(a,offsets[i]),uv(b,offsets[i+1]),uv(c,offsets[i+1])])
                addtri(groups,m['piece_edge'],[a,c,e],[uv(a,offsets[i]),uv(c,offsets[i+1]),uv(e,offsets[i])])
            else:
                uv=lambda v:face_uv(v,front if r>3 else reverse,r<3)
                addtri(groups,m['pieces'],[a,b,c],[uv(a),uv(b),uv(c)])
                addtri(groups,m['pieces'],[a,c,e],[uv(a),uv(c),uv(e)])
    return g.mesh('Piece_'+name,groups)

def turned_foot(g,m):
    height=LAYOUT['board_top']-LAYOUT['board_body']
    profile=[(0,.21),(.05,.31),(.20,.44),(.38,.47),(.52,.41),(.65,.26),(.77,.28),(.86,.34),(1,.32)]
    groups={};segments=32
    for j in range(len(profile)-1):
        for i in range(segments):
            vertices=[]
            for row,col in [(j,i),(j,i+1),(j+1,i+1),(j+1,i)]:
                t,r=profile[row];angle=col/segments*math.tau
                r*=1+.055*math.cos(angle*8)
                vertices.append([math.cos(angle)*r,t*height,math.sin(angle)*r])
            a,b,c,d=vertices
            # Outward winding, with continuous grain around the turned leg.
            addtri(groups,m['side'],[a,c,b],[[i/segments,j/8],[(i+1)/segments,(j+1)/8],[(i+1)/segments,j/8]])
            addtri(groups,m['side'],[a,d,c],[[i/segments,j/8],[i/segments,(j+1)/8],[(i+1)/segments,(j+1)/8]])
    for fraction,radius in [profile[0],profile[-1]]:
        for i in range(segments):
            edge=[]
            for col in [i,i+1]:
                angle=col/segments*math.tau;r=radius*(1+.055*math.cos(angle*8))
                edge.append([math.cos(angle)*r,fraction*height,math.sin(angle)*r])
            verts=[[0,fraction*height,0],edge[0],edge[1]]
            if fraction>0:verts=[verts[0],verts[2],verts[1]]
            addtri(groups,m['side'],verts,[[.5,.5],[0,0],[1,0]])
    return g.mesh('Eight-lobed turned kaya foot',groups,smooth=True)

def board_nodes(g,m):
    nodes=[]
    nodes.append(g.node('Board',box(g,'Board chamfered solid',LAYOUT['board_width'],LAYOUT['board_depth'],LAYOUT['board_body'],m['board'],m['side'],.055),(0,LAYOUT['board_top']-LAYOUT['board_body'],0)))
    leg=turned_foot(g,m)
    for x in [-3.5,3.5]:
        for z in [-4.55,4.55]:nodes.append(g.node('Board foot',leg,(x,0,z)))
    return nodes

def tray_nodes(g,m,x=0,z=0):
    nodes=[]
    nodes.append(g.node('Komadai / tray',box(g,'Komadai top',LAYOUT['tray_width'],LAYOUT['tray_depth'],.19,m['tray'],m['tray'],.045),(x,LAYOUT['tray_top']-.19,z)))
    nodes.append(g.node('Komadai stem',box(g,'Komadai stem mesh',.38,.54,LAYOUT['tray_top']-.33,m['tray'],m['tray'],.02),(x,.14,z)))
    nodes.append(g.node('Komadai foot',box(g,'Komadai foot mesh',2.2,2.45,.14,m['tray'],m['tray'],.025),(x,0,z)))
    return nodes

g=GLB(); m=materials(g)
floor=box(g,'Tatami floor',28,24,.07,m['tatami'],m['tatami'],.008)
# Repeated weave UVs, independent of physical floor dimensions.
for prim in g.doc['meshes'][floor]['primitives']:
    acc=g.doc['accessors'][prim['attributes']['TEXCOORD_0']]; view=g.doc['bufferViews'][acc['bufferView']]
    offset=view['byteOffset']; size=view['byteLength']
    vals=np.frombuffer(g.buf[offset:offset+size],dtype='<f4').copy().reshape(-1,2); vals*= [12,10]
    g.buf[offset:offset+size]=vals.astype('<f4').tobytes()
g.node('Tatami environment',floor,(0,-.07,0))
border=box(g,'Tatami seam',.10,24,.008,m['border'],m['border'],.001)
for x in [-10.5,10.5]:g.node('Tatami cloth seam',border,(x,.001,0))
board_nodes(g,m)
for side_sign in [-1,1]:
    tray_nodes(g,m,side_sign*LAYOUT['tray_x'],side_sign*LAYOUT['tray_z'])
meshes={s[0]:piece_mesh(g,m,s) for s in specs}
back=['lance','knight','silver','gold','jewel','gold','silver','knight','lance']
for player,sgn in [('sente',1),('gote',-1)]:
    rot=None if sgn==1 else [0,1,0,0]
    for col,name in enumerate(back):
        if player=='gote' and name=='jewel':name='king'
        g.node(f'{player}_{name}_{col}',meshes[name],((col-4)*.98,LAYOUT['board_top']+.015,sgn*4.32),rot,extras={'piece':name,'owner':player,'square':[col,8 if sgn==1 else 0]})
    for name,x in [('rook',2.94*sgn),('bishop',-2.94*sgn)]:
        g.node(f'{player}_{name}',meshes[name],(x,LAYOUT['board_top']+.015,sgn*3.24),rot,extras={'piece':name,'owner':player})
    for col in range(9):g.node(f'{player}_pawn_{col}',meshes['pawn'],((col-4)*.98,LAYOUT['board_top']+.015,sgn*2.16),rot,extras={'piece':'pawn','owner':player})
g.doc['extras']={'version':'art-review-v1','units':'1 unit = 40 mm','boardTopY':LAYOUT['board_top'],'grid':{'columns':9,'rows':9,'cellWidth':.98,'cellDepth':1.08},'pieceCount':40,'note':'Visual asset review, not a playable app; original geometry, reference-guided generated wood and licensed Ryoko glyphs.'}
g.save(OUT/'shogi-scene.glb')

for spec in specs:
    single=GLB(); mm=materials(single); mesh=piece_mesh(single,mm,spec)
    single.node('Piece_'+spec[0],mesh,extras={'front':labels[spec[1]],'back':None if spec[2] is None else labels[spec[2]],'tip':'-Z','baseY':0})
    single.save(OUT/('piece-'+spec[0]+'.glb'))
single=GLB(); mm=materials(single); board_nodes(single,mm); single.save(OUT/'board.glb')
single=GLB(); mm=materials(single); tray_nodes(single,mm); single.save(OUT/'komadai.glb')

# Arrange front and promoted reverse faces as a separate inspectable asset.
sheet=GLB(); mm=materials(sheet)
for i,spec in enumerate(specs):
    mesh=piece_mesh(sheet,mm,spec)
    sheet.node('Front '+spec[0],mesh,((i-4)*1.12,0,-.78))
    if spec[2] is not None:
        sheet.node('Promoted '+spec[0],mesh,((i-4)*1.12,spec[5]+.04,.78),[0,0,1,0])
sheet.save(OUT/'piece-study.glb')

manifest={'version':1,'coordinateSystem':'+Y up, -Z piece tip; 1 unit = 40 mm','scene':'shogi-scene.glb','board':'board.glb','tray':'komadai.glb','pieces':[{'file':'piece-'+s[0]+'.glb','name':s[0],'front':labels[s[1]],'reverse':labels[s[2]] if s[2] is not None else None,'size':[s[3],s[5],s[4]]} for s in specs],'sources':{'geometry':'Original procedural construction','wood':'Reference-guided generated wood; assets/materials/photographic-v042/prompts.md','tatami':'Procedural GLB fallback; runtime uses existing generated igusa-rush.png','calligraphy':'Ryoko style by LuffyKudo; CC-BY-SA-4.0 source and derivatives; assets/calligraphy/ryoko/provenance.json','artworkURL':'https://github.com/LuffyKudo/Shogi-Themes/tree/af44470b85b160fa01e23b2a63d8a91232cf34c3/Ryoko'},'status':'Art review; not yet profiled on Android'}
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'files':len(list(OUT.glob('*.glb'))),'sceneBytes':(OUT/'shogi-scene.glb').stat().st_size,'uniqueTriangles':sum(g.doc['accessors'][p['attributes']['POSITION']]['count']//3 for mesh in g.doc['meshes'] for p in mesh['primitives']),'pieces':40},indent=2))


