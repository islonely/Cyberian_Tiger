module dom

import strings { new_builder }

// Element reprensents an HTML DOM element/tag.
[heap]
pub struct Element {
	AbstractNode
mut:
	attributes []&Attribute
pub mut:
	namespace_uri string
	prefix        string
	local_name    string
	tag_name      string
}

pub fn (e &Element) html() string {
	mut bldr := new_builder(500)
	bldr.write_string('<$e.local_name')
	for attr in e.attributes {
		bldr.write_string(' $attr.name="$attr.value"')
	}
	bldr.write_string('>')
	if e.text_content.len > 0 {
		str := e.text_content.replace('\n', '\\n').replace('\t', '\\t').replace('\f', '\\f')
		bldr.write_string('\n$str')
	}
	for child in e.child_nodes {
		if child is Element {
			bldr.write_string('\n' + child.html())
		}
	}
	bldr.write_string('\n</$e.local_name>')
	return bldr.str()
}

// not standard compliant; use `fn Document.createElement`.
pub fn new_element(namespace_uri string, prefix string, local_name string) &Element {
	return &Element{
		namespace_uri: namespace_uri
		prefix: prefix
		local_name: local_name
		tag_name: if prefix.len == 0 {
			local_name
		} else {
			'$prefix:$local_name'
		}
	}
}

// children returns the child nodes as `Element`s
pub fn (n &AbstractNode) children() []&Element {
	mut els := []&Element{cap: n.child_nodes.len}
	for i in 0 .. n.child_nodes.len {
		els << &(n.get_child(i) as Element)
	}
	return els
}

// get_attribute returns the value of an attribute if the `qualified_name`
// matches one of the attributes of the Element. Returns an error if none
// are found.
pub fn (e &Element) get_attribute(qualified_name string) ?string {
	for a in e.attributes {
		if a.get_qualified_name() == qualified_name {
			return a.value
		}
	}

	return error('No matching attribute found.')
}

// get_attribute_ns returns the value of an attribute if `namespace_uri`
// and `local_name` match one of the attributes of the Element. Returns
// an error if none are found.
pub fn (e &Element) get_attribute_ns(namespace_uri string, local_name string) ?string {
	for a in e.attributes {
		if a.namespace_uri == namespace_uri && a.local_name == local_name {
			return a.value
		}
	}

	return error('No matching attribute found.')
}

// set_attribute sets the value of an attribute in the Element if it
// exists. Otherwise an error is returned.
pub fn (mut e Element) set_attribute(qualified_name string, value string) ? {
	for mut a in e.attributes {
		if a.get_qualified_name() == qualified_name {
			a.value = value
			return
		}
	}

	return error('No matching attribute found.')
}

// set_attribute sets the value of an attribute in the Element if it
// exists. Otherwise an error is returned.
pub fn (mut e Element) set_attribute_ns(namespace_uri string, local_name string, value string) ? {
	for mut a in e.attributes {
		if a.namespace_uri == namespace_uri && a.local_name == local_name {
			a.value = value
			return
		}
	}

	return error('No matching attribute found.')
}

// remove_attribute deletes an attribute if one is found with a
// matching `qualified_name`. If none match, then an error is
// returned.
pub fn (mut e Element) remove_attribute(qualified_name string) ? {
	for i, a in e.attributes {
		if a.get_qualified_name() == qualified_name {
			e.attributes.delete(i)
			return
		}
	}

	return error('No matching attribute found.')
}

// remove_attribute_ns deletes an attribute if one if found matching
// `namespace_uri` and `local_name`. If none match, then an error is
// returned.
pub fn (mut e Element) remove_attribute_ns(namespace_uri string, local_name string) ? {
	for i, a in e.attributes {
		if a.namespace_uri == namespace_uri && a.local_name == local_name {
			e.attributes.delete(i)
			return
		}
	}

	return error('No matching attribute found.')
}

// has_attribute returns whether or not the Element has an attribute
// with a matching `qualified_name`.
pub fn (e &Element) has_attribute(qualified_name string) bool {
	for a in e.attributes {
		if a.get_qualified_name() == qualified_name {
			return true
		}
	}
	return false
}

// has_attribute_ns returns whether or not the Element has an
// attribute with a matching `namespace_uri` and `local_name`.
pub fn (e &Element) has_attribute_ns(namespace_uri string, local_name string) bool {
	for a in e.attributes {
		if a.namespace_uri == namespace_uri && e.local_name == local_name {
			return true
		}
	}
	return false
}

// get_attribute_node returns the Attribute node from `attributes`
// with a matching `qualified_name` or an error if none match.
pub fn (e &Element) get_attribute_node(qualified_name string) ?&Attribute {
	for i := 0; i < e.attributes.len; i++ {
		if e.attributes[i].get_qualified_name() == qualified_name {
			return e.attributes[i]
		}
	}

	return error('No matching attribute found.')
}

// get_attribute_node_ns returns the `Attribute` node from `attributes`
// with a matching `namespace_uri` and `local_name` or an error
// if no matches are found.
pub fn (e &Element) get_attribute_node_ns(namespace_uri string, local_name string) ?&Attribute {
	for i := 0; i < e.attributes.len; i++ {
		if e.attributes[i].namespace_uri == namespace_uri
			&& e.attributes[i].local_name == local_name {
			return e.attributes[i]
		}
	}

	return error('No matching attributes found.')
}

// set_attribute_node pushes a `Attribute` to `attributes`.
[inline]
pub fn (mut e Element) set_attribute_node(a &Attribute) {
	e.attributes << a
}

// get_elements_by_tag_name returns an array of `Element`s that
// have a qualified name matching the one provided.
pub fn (e &Element) get_elements_by_tag_name(qualified_name string) []&Element {
	mut els := []&Element{cap: e.child_nodes.len}
	for i, _ in e.child_nodes {
		c := &(e.get_child(i) as Element)
		if c.get_qualified_name() == qualified_name {
			els << c
		}
	}
	return els
}

// get_elements_by_tag_name returns an array of `Element`s that
// have a matching `namespace_uri` and `local_name`.
pub fn (e &Element) get_elements_by_tag_name_ns(namespace_uri string, local_name string) []&Element {
	mut els := []&Element{cap: e.child_nodes.len}
	for i, _ in e.child_nodes {
		c := &(e.get_child(i) as Element)
		if c.namespace_uri == namespace_uri && c.local_name == local_name {
			els << c
		}
	}
	return els
}

// inner_html returns the HTML string equivalent of this
// `Element`'s child `Element`s.
pub fn (e &Element) inner_html() string {
	mut bldr := new_builder(1000)
	for child in e.child_nodes {
		if child is Element {
			bldr.write_string(child.html())
		} else if child is Text {
			bldr.write_string(child.str())
		}
	}
	return bldr.str()
}

pub fn (e &Element) outer_html() string {
	return 'warning: outer_html function not yet implemented'
}

// get_qualified_name returns the qualified name of `Element`.
pub fn (e &Element) get_qualified_name() string {
	return if e.prefix.len == 0 {
		e.local_name
	} else {
		'$e.prefix:$e.local_name'
	}
}

// remove_child deletes the `Node` if it exists or returns
// an error.
pub fn (mut e Element) remove_child(n &Node) ? {
	index := e.child_nodes.index(n)
	if index >= 0 {
		e.child_nodes.delete(index)
	} else {
		return error('No child node matches provided node.')
	}
}

// remove deletes this `Element` from the parent.
pub fn (e &Element) remove() ? {
	mut parent := ptr_optional(&e.parent_node) or { return error('Element has no parent.') }
	mut parent_element := &(parent as Element)
	parent_element.remove_child(e) ?
}
