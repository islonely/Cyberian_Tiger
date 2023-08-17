module dom

// https://html.spec.whatwg.org/multipage/semantics.html#htmllinkelement
pub struct HTMLLinkElement {
	HTMLElement // LinkStyle
pub mut:
	href            string
	cross_origin    ?string
	rel             string
	@as             string
	rel_list        []string
	media           string
	integrity       string
	href_lang       string
	@type           string
	sizes           []string
	image_srcset    string
	image_sizes     string
	referrer_policy string
	blocking        []string
	disabled        bool
	fetch_priority  string
	// obsolete
	charset string
	rev     string
	target  string
}
