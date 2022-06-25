module dom

// Attribute represents and HTML attribute (id="someId").
[heap]
struct Attribute {
	AbstractNode
pub mut:
	namespace_uri string
	prefix        string
	local_name    string
	name          string
	owner_element &Element = 0
__global:
	value string
}

// str returns a string representation of `Attribute`.
pub fn (a Attribute) str() string {
	return 'Attribute{\n\tnamespace_uri: $a.namespace_uri\n\tprefix: $a.prefix\n\tlocal_name: $a.local_name\n\tname: $a.name\n\tvalue: $a.value\n\towner_element: ${voidptr(a.owner_element)}\n}'
}

// html returns an HTML representation of `Attribute`.
pub fn (a Attribute) html() string {
	return '$a.name="$a.value"'
}

// new_attribute instantiates an `Attribute`.
pub fn new_attribute(namespace string, prefix string, local_name string, value string, element &Element) &Attribute {
	name := if prefix.len == 0 {
		local_name
	} else {
		'$prefix:$local_name'
	}
	return &Attribute{AbstractNode{}, namespace, prefix, local_name, name, element, value}
}

// get_qualified_name returns the qualified name of an `Attribute`.
pub fn (a &Attribute) get_qualified_name() string {
	return if a.prefix.len == 0 {
		a.local_name
	} else {
		'$a.prefix:$a.local_name'
	}
}
