import bpy, json, os, sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
bpy.ops.wm.open_mainfile(filepath=os.path.join(root, 'source_assets/female_hunter/Female hunter rigged.blend'))
report = {'objects': [], 'materials': []}
for obj in bpy.data.objects:
    item = {'name': obj.name, 'type': obj.type, 'dimensions': list(obj.dimensions), 'scale': list(obj.scale), 'location': list(obj.location)}
    if obj.type == 'ARMATURE':
        item['bones'] = [{'name': b.name, 'parent': b.parent.name if b.parent else None, 'head': list(b.head_local), 'tail': list(b.tail_local)} for b in obj.data.bones]
    if obj.type == 'MESH':
        item['vertices'] = len(obj.data.vertices)
        item['groups'] = [g.name for g in obj.vertex_groups]
    report['objects'].append(item)
for mat in bpy.data.materials:
    report['materials'].append({'name':mat.name, 'images':[{'node':n.name,'image':n.image.name,'path':n.image.filepath} for n in mat.node_tree.nodes if n.type=='TEX_IMAGE' and n.image] if mat.node_tree else []})
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=os.path.join(root,'source_assets/motions/Gril_motion/Jogging.fbx'))
report['motion'] = [{'name':o.name,'type':o.type,'scale':list(o.scale),'bones':[{'name':b.name,'parent':b.parent.name if b.parent else None,'head':list(b.head_local),'tail':list(b.tail_local)} for b in o.data.bones] if o.type=='ARMATURE' else []} for o in bpy.data.objects]
report['actions'] = [{'name':a.name, 'range':list(a.frame_range)} for a in bpy.data.actions]
with open(os.path.join(root,'tools/asset_inspection.json'),'w',encoding='utf-8') as out: json.dump(report,out,indent=2)
print('ASSET_INSPECTION_COMPLETE')
