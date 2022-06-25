module dom

pub struct Comment {
	AbstractNode
__global:
	data string
}

// html returns the HTML representation of `Comment`.
[inline]
pub fn (c Comment) html() string {
	return '<!--$c.data-->'
}
