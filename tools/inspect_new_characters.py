import bpy, os, re, json
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
report={}
for key,file in [('rin','source_assets/rin/FBX with Atlas/Rin (Atlas FBX).fbx'),('aki','source_assets/aki/Aki SchoolGirl.glb')]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if file.endswith('fbx'): bpy.ops.import_scene.fbx(filepath=os.path.join(ROOT,file))
    else: bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT,file))
    objects=[]
    for o in bpy.data.objects:
        item={'name':o.name,'type':o.type,'scale':list(o.scale),'dimensions':list(o.dimensions),'location':list(o.location),'parent':o.parent.name if o.parent else None}
        if o.type=='ARMATURE': item['bones']=[{'name':b.name,'parent':b.parent.name if b.parent else None,'head':list(o.matrix_world@b.head_local),'tail':list(o.matrix_world@b.tail_local)} for b in o.data.bones]
        if o.type=='MESH': item.update({'vertices':len(o.data.vertices),'groups':[g.name for g in o.vertex_groups],'materials':[s.material.name if s.material else None for s in o.material_slots]})
        objects.append(item)
    report[key]={'objects':objects,'materials':[{'name':m.name,'color':list(m.diffuse_color),'images':[{'node':n.name,'image':n.image.name,'path':n.image.filepath,'size':list(n.image.size)} for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image] if m.node_tree else []} for m in bpy.data.materials]}
text=open(os.path.join(ROOT,'source_assets/character/All/Character.ma'),encoding='utf-8',errors='replace').read()
blocks=re.split(r'(?=^createNode )',text,flags=re.M)
nodes=[]
for block in blocks:
    match=re.match(r'createNode (\S+).*?-n "([^"]+)"(?: -p "([^"]+)")?',block)
    if not match: continue
    type,name,parent=match.groups()
    if type not in ['joint','mesh','transform','skinCluster','file','shadingEngine','aiToon','lambert','blinn']:continue
    attrs=re.findall(r'setAttr[^;]*;',block,re.S)
    nodes.append({'type':type,'name':name,'parent':parent,'attrs':[(a[:650]+'...' if len(a)>650 else a) for a in attrs if type not in ['transform'] or re.search(r'"\.(t|r|s|jo)"',a)]})
report['maya']={'nodes':nodes,'connections':re.findall(r'connectAttr[^;]*;',text)[:300]}
with open(os.path.join(ROOT,'tools/new_asset_inspection.json'),'w',encoding='utf-8') as f:json.dump(report,f,indent=2)
print('NEW_ASSET_INSPECTION_COMPLETE',flush=True)
