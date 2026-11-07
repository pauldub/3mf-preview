from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
root=Path(__file__).parent/'fixtures'
root.mkdir(exist_ok=True)
mesh='<object id="1"><mesh><vertices><vertex x="0" y="0" z="0"/><vertex x="20" y="0" z="0"/><vertex x="0" y="20" z="0"/><vertex x="0" y="0" z="20"/></vertices><triangles><triangle v1="0" v2="2" v3="1"/><triangle v1="0" v2="1" v3="3"/><triangle v1="0" v2="3" v3="2"/><triangle v1="1" v2="2" v3="3"/></triangles></mesh></object>'
def model(resources,build):
    return f'<model xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02" xmlns:p="http://schemas.microsoft.com/3dmanufacturing/production/2015/06"><resources>{resources}</resources><build>{build}</build></model>'
def package(name,main,parts={}):
    with ZipFile(root/(name+'.3mf'),'w',ZIP_DEFLATED) as z:
        z.writestr('_rels/.rels','<Relationships><Relationship Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel" Target="/3D/main.model"/></Relationships>')
        z.writestr('3D/main.model',main)
        for path,data in parts.items(): z.writestr(path,data)
package('tetrahedron',model(mesh,'<item objectid="1"/>'))
package('assembly',model('<object id="2"><components><component objectid="1" p:path="/3D/part.model" transform="1 0 0 0 1 0 0 0 1 40 0 0"/></components></object>','<item objectid="2"/>'),{'3D/part.model':model(mesh,'')})
package('cycle',model('<object id="1"><components><component objectid="1"/></components></object>','<item objectid="1"/>'))
package('bad-index',model(mesh.replace('v1="0"','v1="99"'),'<item objectid="1"/>'))
package('empty',model(mesh,''))
(root/'corrupt.3mf').write_bytes(b'not a zip')

# Four plates exercise both rows, repeated objects, and an empty bed.
import json
settings = json.dumps({'printable_area':['0x0','200x0','200x150','0x150']})
layout = '<config>' + ''.join(f'<plate><metadata key="plater_name" value="Batch {i+1}"/></plate>' for i in range(4)) + '</config>'
items = ''.join(f'<item objectid="1" transform="1 0 0 0 1 0 0 0 1 {x} {y} 0"/>' for x,y in [(50,50),(290,50),(50,-130)])
package('plates',model(mesh,items),{'Metadata/project_settings.config':settings,'Metadata/model_settings.config':layout})
package('bad-bed',model(mesh,'<item objectid="1"/>'),{'Metadata/project_settings.config':'{"printable_area":["nanx0","1x0","1x1"]}'})
