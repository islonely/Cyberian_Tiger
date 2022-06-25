module dom

const doctype_missing = '\0\0\0\0\0\0\0\0'

[heap]
pub struct Doctype {
	AbstractNode
__global:
	name      string
	public_id string
	system_id string
}

[inline]
pub fn (d Doctype) html() string {
	return '<!DOCTYPE $d.name' + if d.public_id != doctype_missing { ' public="$d.public_id"' } else {''} + if d.system_id != doctype_missing {' system="$d.system_id"'} else {''} + '>'
}