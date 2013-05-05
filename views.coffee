designs =
  posts:
    by_date: (doc) ->
      if doc.type is 'post'
        emit doc.created_at, null
    by_slug: (doc) ->
      if doc.type is 'post'
        emit doc.slug, null

exports.push = (db) ->
	for d of designs
		do (d) ->
      for v of designs[d]
        if typeof designs[d][v] is 'function'
          designs[d][v] = { map: designs[d][v] }
      db.get '_design/' + d, (err, res) ->
        # if (err) { console.log(err); return }
        data = JSON.stringify designs[d], (k, val) ->
          if typeof val is 'function'
            val.toString()
          else
            val
        if res and data == JSON.stringify(res.views)
          #console.info("_design/" + d + " up to date (rev " + res._rev + ")")
        else
          db.save '_design/' + d, designs[d], (err, res) ->
            throw err if err
            console.info "Updated " + res.id + " (rev " + res.rev + ")"
