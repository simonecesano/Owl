// summarize.js

(function($) {
    // what if selection is a function?
    $.fn.summarize = function(selector, is_same, if_true, if_false) {
	var a = $(this);
	var b = $(this).prevAll(selector).first();
	if (is_same(a, b)) {
	    if_true(a, b);
	} else {
	    if_false(a, b);
	}
    };
    $.fn.colSpan = function(c) {
	if (arguments.length > 0) {
	    console.log(arguments[0]);
	    this.attr('colspan', arguments[0]);
	    return this
	} else {
	    return +this.attr('colspan') || 1
	}
    };
    $.fn.rowSpan = function(c) {
	if (arguments.length > 0) {
	    this.attr('rowspan', arguments[0]);
	    return this
	} else {
	    return +this.attr('rowspan') || 1
	}
    };
}(jQuery));
