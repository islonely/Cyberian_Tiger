module dom

[heap]
struct Text {
	AbstractNode
__global:
	data string
}

// str returns the text data from `Text`.
[inline]
pub fn (t Text) str() string {
	return t.data
}