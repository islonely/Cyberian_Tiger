module parser

import strings { Builder }

// converts a-Z to a-z; no effect on anything else
fn rune_to_lower(r rune) rune {
	return if r >= 0x41 && r <= 0x5a {
		(r + 0x20)
	} else {
		r
	}
}

// builder_contents returns the value of a strings.Builder without
// terminating the builder like strings.Builder.str does.
[inline]
fn builder_contents(bldr Builder) string {
	return bldr.bytestr()
}

// is_surrogate returns whether or not a rune is a surrogate
// character.
[inline]
fn is_surrogate(r rune) bool {
	return if r >= 0xd800 && r <= 0xdfff {
		true
	} else {
		false
	}
}

// is_noncharacter returns whether or not a rune is a noncharacter.
[inline]
fn is_noncharacter(r rune) bool {
	return if (r >= 0xfdd0 && r <= 0xfdef) || r in [
		rune(0xfffe), 0xffff, 0x1fffe, 0x1ffff, 0x2fffe,
		0x2ffff, 0x3fffe, 0x3ffff, 0x4fffe, 0x4ffff, 0x5fffe,
		0x5ffff, 0x6fffe, 0x6ffff, 0x7fffe, 0x7ffff, 0x8fffe,
		0x8ffff, 0x9fffe, 0x9ffff, 0xafffe, 0xaffff, 0xbfffe,
		0xbffff, 0xcfffe, 0xcffff, 0xdfffe, 0xdffff, 0xefffe,
		0xeffff, 0xffffe, 0xfffff, 0x10fffe, 0x10ffff
	] {
		true
	} else {
		false
	}
}

// is_c0_control returns whether or not a rune is a C0 control
// character.
[inline]
fn is_c0_control(r rune) bool {
	return if r >= 0x0000 && r <= 0x001f {
		true
	} else {
		false
	}
}

// is_control returns whether or not a rune is a control character.
[inline]
fn is_control(r rune) bool {
	return if is_c0_control(r) || (r >= 0x007f && r <= 0x009f) {
		true
	} else {
		false
	}
}