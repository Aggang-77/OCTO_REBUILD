"""Add waist-anchored mid/hem chains and skin only the skirt fabric."""
import bpy, bmesh, math
from mathutils import Vector

def build_skirt(rig, meshes, key):
    center=rig.data.bones['Hips'].head_local.copy()
    selected={}
    for obj in meshes:
        indices=set()
        for poly in obj.data.polygons:
            mat=obj.data.materials[poly.material_index] if poly.material_index<len(obj.data.materials) else None
            name=mat.name.lower() if mat else ''
            if (key=='lily' and obj.name.startswith('Sk4')) or (key=='aki' and 'bottoms' in name):
                indices.update(poly.vertices)
            elif key=='lily_orange' and 'coat' in obj.name.lower():
                if all(obj.data.vertices[v].co.z<center.z+0.025 for v in poly.vertices):indices.update(poly.vertices)
            elif key=='rin' and 'atlas' in name and not name.startswith('hunterhair'):
                # The atlas also contains the blouse. Clip selection below the waist.
                if all(center.z-0.40 < obj.data.vertices[v].co.z < center.z+0.025 for v in poly.vertices):
                    indices.update(poly.vertices)
        if indices:selected[obj]=indices
    vertices=[obj.data.vertices[i].co for obj,ids in selected.items() for i in ids]
    if not vertices:raise RuntimeError('No skirt fabric selected: '+key)
    waist=max(v.z for v in vertices);hem=min(v.z for v in vertices)
    if waist-hem<0.12:raise RuntimeError('Skirt selection too short: '+key)
    mid=(waist+hem)*0.5
    def radius_at(z):
        radii=sorted(math.hypot(v.x-center.x,v.y-center.y) for v in vertices if abs(v.z-z)<(waist-hem)*0.20)
        return radii[int(len(radii)*0.65)] if radii else 0.18
    radii=[radius_at(z) for z in (waist,mid,hem)]
    bpy.context.view_layer.objects.active=rig;rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for panel in range(8):
        a=panel*math.tau/8;direction=Vector((math.cos(a),math.sin(a),0))
        points=[Vector((center.x,center.y,z))+direction*r for z,r in zip((waist,mid,hem),radii)]
        parent=rig.data.edit_bones['Hips']
        for segment,suffix in enumerate(('Mid','Hem')):
            bone=rig.data.edit_bones.new(f'ClothPanel_{panel:02}_{suffix}')
            bone.head=points[segment];bone.tail=points[segment+1]
            bone.parent=parent;bone.use_connect=segment==1;parent=bone
    bpy.ops.object.mode_set(mode='OBJECT')
    for obj,ids in selected.items():
        originals=list(obj.data.materials);materials={}
        for poly in obj.data.polygons:
            if not all(v in ids for v in poly.vertices):continue
            old=poly.material_index
            if old not in materials:
                material=originals[old].copy();material.name='HunterSkirt_'+originals[old].name
                materials[old]=len(obj.data.materials);obj.data.materials.append(material)
            poly.material_index=materials[old]
        hips=obj.vertex_groups.get('Hips') or obj.vertex_groups.new(name='Hips')
        groups={(p,s):obj.vertex_groups.new(name=f'ClothPanel_{p:02}_{s}') for p in range(8) for s in ('Mid','Hem')}
        for i in ids:
            vertex=obj.data.vertices[i];p=vertex.co
            for assignment in list(vertex.groups):obj.vertex_groups[assignment.group].remove([i])
            t=max(0,min(1,(waist-p.z)/(waist-hem)))
            a=((math.atan2(p.y-center.y,p.x-center.x)%math.tau)/math.tau)*8
            panel=int(a);mix=a-panel
            # Smooth transition from the fixed waistband through middle to hem.
            w_hips=max(0,1-t*2);w_hem=max(0,t*2-1);w_mid=1-w_hips-w_hem
            if w_hips>0:hips.add([i],w_hips,'REPLACE')
            for index,weight in ((panel,1-mix),((panel+1)%8,mix)):
                for suffix,value in (('Mid',w_mid),('Hem',w_hem)):
                    if weight*value>0.00001:groups[index,suffix].add([i],weight*value,'REPLACE')
        # Small faces prevent a leg from crossing between widely spaced cloth
        # vertices. Subdivision interpolates the UVs and newly authored weights.
        bm=bmesh.new();bm.from_mesh(obj.data)
        for iteration in range(3):
            edges=[e for e in bm.edges if e.calc_length()>0.045 and all(f.material_index in materials.values() for f in e.link_faces)]
            if not edges:break
            bmesh.ops.subdivide_edges(bm,edges=edges,cuts=1,use_grid_fill=True)
        bmesh.ops.triangulate(bm,faces=[f for f in bm.faces if f.material_index in materials.values()])
        bm.to_mesh(obj.data);bm.free();obj.data.update()
    print('SKIRT_RIG',key,'vertices',len(vertices),'waist/mid/hem',waist,mid,hem,'radii',radii,flush=True)
