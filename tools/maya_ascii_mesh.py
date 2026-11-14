"""Read mesh/UV/bind-pose/skin data only from Maya ASCII. Never execute MEL."""
import bpy, re, os, math
from mathutils import Matrix, Vector, Euler
NUM=r'[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?'

def load_maya_character(filename):
    text=open(filename,encoding='utf-8',errors='replace').read()
    nodes={}; latest={}; ordered=[]
    def resolve(name):
        return name if name in nodes else latest.get(name.split('|')[-1],name)
    for block in re.split(r'(?=^createNode )',text,flags=re.M):
        match=re.match(r'createNode (\S+).*?-n "([^"]+)"(?: -p "([^"]+)")?',block)
        if not match: continue
        kind,name,parent=match.groups()
        parent=resolve(parent) if parent else None
        full=(parent+'|' if parent else '|')+name
        attrs={}
        for attr in re.finditer(r'setAttr\s+([^;]*);',block,re.S):
            a=re.search(r'"(\.[^"]+)"(.*)',attr[1],re.S)
            if a and a[2].strip(): attrs[a[1]]=re.sub(r'^\s*-type\s+"[^"]+"','',a[2]).strip()
        node={'type':kind,'name':name,'parent':parent,'attrs':attrs,'full':full}
        nodes[full]=node; latest[name]=full; ordered.append(node)
    connections=[]
    for a,b in re.findall(r'connectAttr(?:\s+-\w+)*\s+"([^"]+)"\s+"([^"]+)"[^;]*;',text):
        an,aa=a.split('.',1); bn,ba=b.split('.',1)
        connections.append((resolve(an),aa,resolve(bn),ba))
    incoming={}
    for a,aa,b,ba in connections: incoming.setdefault(b,[]).append((a,aa,ba))
    def values(value): return [float(n) for n in re.findall(NUM,value)]
    def array(node,key,width):
        result={}
        for attr,data in node['attrs'].items():
            match=re.fullmatch(re.escape(key)+r'\[(\d+)(?::(\d+))?\]',attr)
            if not match:continue
            start=int(match[1]); nums=values(data)
            for i in range(len(nums)//width): result[start+i]=nums[i*width:(i+1)*width]
        return [result.get(i,[0.0]*width) for i in range(max(result)+1)] if result else []
    def upstream(node,kind,visited=None):
        visited=set() if visited is None else visited
        if node in visited:return None
        visited.add(node)
        if node in nodes and nodes[node]['type']==kind:return nodes[node]
        for a,aa,ba in incoming.get(node,[]):
            if ba in ['message','m'] or aa in ['message','m']:continue
            found=upstream(a,kind,visited)
            if found:return found
        return None
    conversion=Matrix.Rotation(math.pi/2,4,'X')
    clusters=[n for n in ordered if n['type']=='skinCluster']
    bind={}; skin_maps={}
    for cluster in clusters:
        influences={}
        for a,aa,b,ba in connections:
            m=re.match(r'ma\[(\d+)\]',ba)
            if b==cluster['full'] and m and nodes.get(a,{}).get('type')=='joint':
                idx=int(m[1]); influences[idx]=a
                pm=cluster['attrs'].get('.pm[%d]'%idx)
                if pm:
                    nums=values(pm)
                    if len(nums)==16:bind[a]=conversion@Matrix([nums[i:i+4] for i in range(0,16,4)]).transposed().inverted()
        skin_maps[cluster['full']]=influences
    armature=bpy.data.armatures.new('LilyRig')
    rig=bpy.data.objects.new('LilyRig',armature); bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active=rig; rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for full,matrix in bind.items():
        bone=armature.edit_bones.new(nodes[full]['name'])
        bone.matrix=matrix@Matrix.Rotation(-math.pi/2,4,'Z')
        bone.length=0.35
    for full in bind:
        parent=nodes[full]['parent']
        while parent in nodes and parent not in bind:parent=nodes[parent]['parent']
        if parent in bind:armature.edit_bones[nodes[full]['name']].parent=armature.edit_bones[nodes[parent]['name']]
    bpy.ops.object.mode_set(mode='OBJECT')
    materials={}
    for n in ordered:
        if n['type']!='shadingEngine':continue
        file=upstream(n['full'],'file')
        mat=bpy.data.materials.new(n['name']); mat.use_nodes=True
        bsdf=mat.node_tree.nodes.get('Principled BSDF'); bsdf.inputs['Roughness'].default_value=0.9
        bsdf.inputs['Specular IOR Level'].default_value=0.15
        if file:
            texture=os.path.basename(file['attrs'].get('.ftn','').strip('"').replace('\\','/'))
            texture=os.path.join(os.path.dirname(filename),'sourceimages','Textures',texture)
            if os.path.isfile(texture):
                image=bpy.data.images.load(texture,check_existing=True)
                tex=mat.node_tree.nodes.new('ShaderNodeTexImage'); tex.image=image
                mat.node_tree.links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
                mat.node_tree.links.new(tex.outputs['Alpha'],bsdf.inputs['Alpha'])
        materials[n['full']]=mat
    def transform(full):
        if full not in nodes:return Matrix.Identity(4)
        n=nodes[full]; a=n['attrs']
        t=values(a.get('.t','0 0 0')); r=values(a.get('.r','0 0 0')); s=values(a.get('.s','1 1 1'))
        local=Matrix.Translation(Vector(t))@Euler(tuple(math.radians(v) for v in r),'XYZ').to_matrix().to_4x4()@Matrix.Diagonal(Vector((*s,1)))
        return transform(n['parent'])@local
    meshes=[]
    for cluster in clusters:
        final=next((nodes.get(b) for a,aa,b,ba in connections if a==cluster['full'] and aa.startswith('og[') and nodes.get(b,{}).get('type')=='mesh'),None)
        input_node=next((a for a,aa,b,ba in connections if b==cluster['full'] and ba=='ip[0].ig'),None)
        original=upstream(input_node,'mesh') if input_node else None
        if not original: original=final
        if not original or not final:continue
        verts=array(original,'.vt',3); edges=array(original,'.ed',3); uvs=array(original,'.uvst[0].uvsp',2)
        if not verts:continue
        faces=[]; face_uv=[]
        for attr,data in original['attrs'].items():
            if not attr.startswith('.fc['):continue
            for line in data.splitlines():
                tokens=line.strip().split()
                if not tokens:continue
                if tokens[0]=='f':
                    signed=[int(i) for i in tokens[2:2+int(tokens[1])]]
                    faces.append([int(edges[e][0] if e>=0 else edges[-e-1][1]) for e in signed]); face_uv.append([])
                elif tokens[0]=='mu' and tokens[1]=='0' and face_uv:
                    face_uv[-1]=[int(i) for i in tokens[3:3+int(tokens[2])]]
        mesh=bpy.data.meshes.new(final['name']); mesh.from_pydata(verts,[],faces); mesh.update()
        obj=bpy.data.objects.new(final['name'],mesh); bpy.context.collection.objects.link(obj)
        mesh.transform(conversion@transform(original['parent']))
        layer=mesh.uv_layers.new(name='UVMap')
        for polygon,indices in zip(mesh.polygons,face_uv):
            for loop,uv in zip(polygon.loop_indices,indices):
                if 0<=uv<len(uvs):layer.data[loop].uv=uvs[uv]
            polygon.use_smooth=True
        slots={}; assigned=False
        for a,aa,b,ba in connections:
            if a not in [final['full'],original['full']] or b not in materials or not aa.startswith('iog'):continue
            if b not in slots:slots[b]=len(slots);mesh.materials.append(materials[b])
            idx=slots[b]
            group='.'+re.sub(r'^iog(?=\.)','iog[0]',aa)+'.gcl' if '.og[' in aa else None
            spec=final['attrs'].get(group,'') if group else ''
            if not spec and group:spec=original['attrs'].get(group,'')
            if not spec and '.og[' in aa:
                group_id=next((src for src,sa,dst,da in connections if dst==a and da==aa+'.gid'),None)
                if group_id:
                    part=next((nodes.get(dst) for src,sa,dst,da in connections if src==group_id and da=='gi' and nodes.get(dst,{}).get('type')=='groupParts'),None)
                    if part:spec=part['attrs'].get('.ic','')
            matches=re.findall(r'f\[(\d+)(?::(\d+))?\]',spec)
            if matches:
                for first,last in matches:
                    for p in range(int(first),int(last or first)+1):
                        if p<len(mesh.polygons):mesh.polygons[p].material_index=idx
            elif len(slots)==1:
                for p in mesh.polygons:p.material_index=idx
            assigned=True
        if not assigned:
            # The deformer output commonly inherits the original shape's set membership.
            name=final['name'].lower()
            preferred='HearUV' if 'sweep' in name else ('BodyDownUV' if 'sk4' in name else 'FaceUV')
            mat=next((m for m in materials.values() if any(n.type=='TEX_IMAGE' and preferred in n.image.name for n in m.node_tree.nodes)),None)
            if mat:mesh.materials.append(mat)
        influences=skin_maps[cluster['full']]
        groups={i:obj.vertex_groups.new(name=nodes[n]['name']) for i,n in influences.items()}
        for attr,data in cluster['attrs'].items():
            match=re.fullmatch(r'\.wl\[(\d+)(?::(\d+))?\]\.w',attr)
            if not match:continue
            nums=values(data); cursor=0; vertex=int(match[1])
            while cursor<len(nums):
                count=int(nums[cursor]);cursor+=1
                for _ in range(count):
                    idx=int(nums[cursor]);weight=nums[cursor+1];cursor+=2
                    if idx in groups and vertex<len(mesh.vertices) and weight>0.0001:groups[idx].add([vertex],weight,'REPLACE')
                vertex+=1
        obj.parent=rig;obj.modifiers.new('Skin','ARMATURE').object=rig
        meshes.append(obj)
        print('MAYA_MESH',obj.name,len(verts),len(faces),[m.name for m in mesh.materials],flush=True)
    print('MAYA_DATA_IMPORTED',len(bind),'bones',len(meshes),'meshes',flush=True)
    return rig,meshes
