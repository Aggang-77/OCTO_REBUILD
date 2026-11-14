import bpy, os, json
root=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
bpy.ops.wm.open_mainfile(filepath=os.path.join(root,'source_assets/female_hunter/Female hunter rigged.blend'))
rig=bpy.data.objects['rig']; rig.data.pose_position='REST'
bpy.context.view_layer.update()
report=[]
for o in bpy.data.objects:
    if o.type!='MESH' or o.name.startswith('WGT-'): continue
    item={'name':o.name,'parent':o.parent.name if o.parent else None,'parent_type':o.parent_type,'parent_bone':o.parent_bone,'groups':[g.name for g in o.vertex_groups], 'materials':[s.material.name if s.material else '' for s in o.material_slots], 'particles':[]}
    for ps in o.particle_systems:
        p=ps.settings
        item['particles'].append({'name':ps.name,'type':p.type,'count':p.count,'hair_step':p.hair_step,'child_type':p.child_type,'child_percent':p.child_percent,'rendered_child_count':p.rendered_child_count,'render_type':p.render_type,'length':p.hair_length,'keys': [list(k.co) for k in ps.particles[0].hair_keys] if len(ps.particles) else []})
    report.append(item)
with open(os.path.join(root,'tools/hair_inspection.json'),'w',encoding='utf-8') as f:json.dump(report,f,indent=2)
scalp=bpy.data.objects['Scalp']
bpy.ops.object.select_all(action='DESELECT'); scalp.select_set(True); bpy.context.view_layer.objects.active=scalp
before=set(bpy.data.objects)
for mod in list(scalp.modifiers):
    if mod.type=='PARTICLE_SYSTEM':
        try:
            bpy.ops.object.modifier_convert(modifier=mod.name)
            print('CONVERTED',mod.name,[(o.name,o.type,len(o.data.vertices) if o.type=='MESH' else 0) for o in set(bpy.data.objects)-before],flush=True)
        except Exception as e: print('CONVERT_ERROR',str(e),flush=True)
print('HAIR_INSPECT_COMPLETE',flush=True)
