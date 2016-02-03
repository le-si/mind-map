
doc_name = location.search or 'document'
fb = new Firebase('https://mind-map.firebaseio.com/')

$last = null
$nodes_by_key = {}

$Node = (data, fb_n)->
	
	fb_n ?= fb_nodes.push(data)
	
	return if $nodes_by_key[fb_n.key()]
	
	cleanup = ->
		if $last and $last isnt $node
			if $last and $last.isEmpty()
				$last.remove()
			$last = null
	
	if $last and $last.isEmpty()
		$last.remove()
	
	previous_content = ''
	
	$node = $last = $('<div contenteditable class="node"></div>')
		.appendTo('#document-content')
		.css
			position: 'absolute'
			padding: '5px'
		.on 'keydown', (e)->
			if e.keyCode is 13 and not e.shiftKey
				e.preventDefault()
				$Node(
					x: data.x + Math.random() * 100 - 50
					y: data.y + 50
				).focus()
		.on 'input', ->
			$node.reposition()
			setTimeout $node.reposition
			content = $node.content()
			if previous_content isnt content
				fb_n.set
					x: data.x
					y: data.y
					_: content
			previous_content = content
		.on 'mousedown', (e)->
			cleanup()
			$last = $node
		.on 'focus', (e)->
			cleanup()
			$last = $node
	
	$nodes_by_key[fb_n.key()] = $node
	
	$node.reposition = ->
		$node.css
			left: data.x - ($node.outerWidth() / 2)
			top: data.y - ($node.outerHeight() / 2)
	
	$node.content = (html)->
		if typeof html is 'string'
			previous_content = html
			unless $node.html() is html
				$node.html(html)
			$node.reposition()
			$node
		else
			$node.html()
	
	$node.isEmpty = ->
		return no if $node.find('img, audio, video, iframe').length
		$node.text().match(/^\s*$/)?
	
	$node.remove = ->
		fb_n.remove()
	
	$node.hide = ->
		$node.css
			opacity: 0
			pointerEvents: 'none'
	
	$node.show = ->
		$node.css
			opacity: ''
			pointerEvents: ''
	
	fb_n.on 'value', (snapshot)->
		value = snapshot.val()
		if value
			data = value
		else
			data._ = ""
		$node.content data._
		$node.reposition()
		if data._
			$node.show()
			fb_n.onDisconnect().cancel()
		else
			$node.hide() unless value?
			fb_n.onDisconnect().remove()
	
	$node

fb_doc = fb.child('documents').child(doc_name)
fb_nodes = fb_doc.child('nodes')

fb_nodes.on 'child_added', (snapshot)->
	# setTimeout needed for deduplication logic
	setTimeout ->
		$Node snapshot.val(), snapshot.ref()

fb_doc.once 'value', (snapshot)->
	# setTimeout needed because of the above one
	setTimeout ->
		unless $('.node:not(:empty)').length
			$Node(
				x: innerWidth / 2
				y: innerHeight / 3
			).focus()
		# What about when two people open up a new document?
		# Should we focus an existing sole empty node?

$doc_content = $('#document-content')

drag_start_offset = x: 0, y: 0
end_drag_velocity = vx: 0, vy: 0
view_offset =
	x: 0, y: 0
	vx: 0, vy: 0
	animating: no
	start_animating: ->
		unless view_offset.animating
			view_offset.animate()
	animate: ->
		view_offset.x += view_offset.vx
		view_offset.y += view_offset.vy
		view_offset.vx *= 0.9
		view_offset.vy *= 0.9
		end_drag_velocity.vx *= 0.5
		end_drag_velocity.vy *= 0.5
		if (
			Math.abs(view_offset.vx) > 0.001 or
			Math.abs(view_offset.vy) > 0.001 or
			Math.abs(end_drag_velocity.vx) > 0.001 or
			Math.abs(end_drag_velocity.vy) > 0.001
		)
			requestAnimationFrame view_offset.animate
			view_offset.animating = yes
		else
			view_offset.animating = no
		$doc_content.css
			transform: "translate(#{view_offset.x.toFixed(3)}px, #{view_offset.y.toFixed(3)}px)"
			# transform: "translate3d(#{view_offset.x.toFixed(3)}px, #{view_offset.y.toFixed(3)}px, 0px)"
			# backfaceVisibility: "hidden"

# TODO: MMB drag even on nodes (although that would likely break linuxy clipboarding)
$('#document-background').on 'mousedown', (e)->
	# unless $(e.target).closest('.node').length # and e.button isnt 1 # MMB
		e.preventDefault()
		unless e.button is 1 # MMB
			$Node(
				x: e.pageX - view_offset.x
				y: e.pageY - view_offset.y
			).focus()
		view_offset.start_animating()
		drag_start_offset.x = view_offset.x - e.pageX
		drag_start_offset.y = view_offset.y - e.pageY
		end_drag_velocity.vx = 0
		end_drag_velocity.vy = 0
		$(window).on 'mousemove', mousemove = (e)->
			prev_view_offset_x = view_offset.x
			prev_view_offset_y = view_offset.y
			view_offset.x = e.pageX + drag_start_offset.x
			view_offset.y = e.pageY + drag_start_offset.y
			end_drag_velocity.vx *= 0.9
			end_drag_velocity.vy *= 0.9
			end_drag_velocity.vx += (view_offset.x - prev_view_offset_x) * 0.3
			end_drag_velocity.vy += (view_offset.y - prev_view_offset_y) * 0.3
			view_offset.start_animating()
		$(window).on 'mouseup', mouseup = (e)->
			$(window).off 'mousemove', mousemove
			$(window).off 'mouseup', mouseup
			unless e.button is 2 # RMB
				view_offset.vx = end_drag_velocity.vx
				view_offset.vy = end_drag_velocity.vy
				view_offset.start_animating()

fb.onAuth (auth_data)->
	if auth_data
		$('#login').hide()
		$('#logged-in').show()
		$('#user-name').text auth_data.google.displayName
		$('#user-image').attr(src: auth_data.google.profileImageURL)
	else
		$('#logged-in').hide()
		$('#login').show()

$('#login').on 'click', (e)->
	fb.authWithOAuthPopup "google", (err, auth_data)->
		if err
			console.log "Login failed", err
		else
			console.log "Authenticated successfully with payload:", auth_data

$('#logout').on 'click', (e)->
	fb.unauth()

$doc_title = $('#document-title')
fb_doc_title = fb_doc.child('title')

$doc_title.on 'input ', (e)->
	fb_doc_title.set $doc_title.val()

fb_doc_title.on 'value', (snapshot)->
	unless $doc_title.val() is snapshot.val()
		$doc_title.val(snapshot.val())

for formatting_option in ['bold', 'italic', 'underline', 'strikethrough']
	do (formatting_option)->
		$('#' + formatting_option).on 'click', (e)->
			document.execCommand formatting_option

if location.hostname.match(/localhost|127\.0\.0\.1/) or location.protocol is 'file:'
	if localStorage.debug
		document.body.classList.add('debug')
else
	fb.child('stats/v2_views').transaction (val)-> (val or 0) + 1
	unless doc_name is 'document'
		fb.child('stats/v2_non_default_views').transaction (val)-> (val or 0) + 1
