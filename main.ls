require! <[fs request bluebird fs-extra ./secret]>

fields = <[id]>

get-token = -> new bluebird (res, rej) ->
  (e,r,b) <- request {
    url: "https://graph.facebook.com/oauth/access_token"
    method: \GET
    qs: {client_id: secret.id, client_secret: secret.secret} <<< {grant_type: "client_credentials"}
  }, _
  if e => return rej e
  res b

get-id-list = (token, pageId) -> new bluebird (res, rej) ->
  list = []
  get-ids = (url) -> new bluebird (res, rej) ->
    (e,r,b) <- request {url: url, method: \GET}
    if e => return rej!
    try
      obj = JSON.parse(b)
      res obj
    catch e
      rej e
  wrapper = (url) ->
    get-ids url
      .then (obj) ->
        list := list.concat obj.data.map(->it.id)
        console.log "#{list.length} fetched."
        if obj.paging and obj.paging.next and !debug => wrapper obj.paging.next
        else res list
      .catch (e) -> rej e
  wrapper(
    "https://graph.facebook.com/#pageId/feed?" +
    ["limit=200","fields=#{fields.join(",")}","access_token=#{token}"].join(\&)
  )

get-posts = (token, list) -> new bluebird (res,rej) ->
  get-item = (url) -> new bluebird (res, rej) ->
    (e,r,b) <- request {url: url, method: \GET}
    if e => return rej e
    res b
  get-items = ->
    console.log "remains: ", list.length
    if list.length == 0 => return res!
    item = list.splice(0, 1).0
    get-item "https://graph.facebook.com/#item"
      .then (str) ->
        str = unescape str.replace(
          /\\u([\d\w]{4})/gi
          (m, g) -> String.fromCharCode parseInt(g, 16)
        )
        fs-extra.mkdirs-sync "posts/#item/"
        fs.write-file-sync "posts/#item/index.json", str
        if debug => list.splice 0
        get-items!
      .catch ->
        console.log it
        rej!
  get-items!

# type = <[reactions comments likes]>
get-parts = (type = \comments, id, token, options)-> new bluebird (res, rej) ->
  list = []
  console.log "fetch #type for #id"
  _ = (after=null) ->
    (e,r,b) <- request {
      url: [
        "https://graph.facebook.com/v2.6/#id/#type?limit=1000"
        options
        "#{if after => 'after=' + after else ''}"
        "access_token=#token"
      ].filter(->it).join("&")
      method: \GET
    }, _
    b = JSON.parse b
    if e or b.error => return rej(e or b)
    list := list ++ (b.[]data or [])
    console.log "#type #{list.length} fetched."
    next = b.{}paging.{}cursors.after
    return res list
    if debug => return res list
    if b.[]data.length and !debug => _ next
    else res list
  _!

get-likes = (id, token) -> get-parts \likes, id, token, "fields=name,id"
get-reactions = (id, token) -> 
  get-parts \reactions, id, token, "fields=name,id,type"
get-comments = (id, token) ->
  get-parts \comments, id, token, "fields=likes,from,message,created_time,id,like_count&filter=stream"

get-comment-list = (token, list) -> new bluebird (res, rej) ->
  _ = ->
    if !list.length => res!
    item = list.splice(0, 1).0
    get-comments item, token
      .then (ret) ->
        fs.write-file-sync "posts/#item/comments", JSON.stringify(ret)
        if debug => return res!
        else _!
      .catch ->
        console.log it
        _!
  _!

get-reaction-list = (token, list) -> new bluebird (res, rej) ->
  _ = ->
    if !list.length => res!
    item = list.splice(0, 1).0
    get-reactions item, token
      .then (ret) ->
        fs.write-file-sync "posts/#item/reactions", JSON.stringify(ret)
        if debug => return res!
        else _!
      .catch ->
        console.log it
        _!
  _!


debug = false
token = null
postlist = null

# 387816094628136 - g0v.general
pageId = 387816094628136

console.log "fetch token..."
get-token!
  .then (ret) ->
    token := JSON.parse(ret).access_token
    console.log "fetch id list from pageId #pageId"
    get-id-list token, pageId
  .then (list) ->
    postlist := JSON.parse(JSON.stringify(list))
    console.log "total posts = #{postlist.length}"
    fs.write-file-sync \list.json, JSON.stringify(list)
    console.log "get posts details..."
    get-posts token, list
  .then ->
    console.log "all posts content fetched."
    list = JSON.parse(JSON.stringify(postlist))
    console.log "get reactions of posts..."
    get-reaction-list token, list
  .then ->
    console.log "all reaction fetched."
    list = JSON.parse(JSON.stringify(postlist))
    console.log "get comments"
    get-comment-list token, list
  .then -> console.log \done.
 
