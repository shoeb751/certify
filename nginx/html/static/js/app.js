var global_t = {"Certificate":"cert","Key":"key","Intermediate Cert":"ic","Full Chain":"chain"}


function create_link(id){
  var id_elem = id + 1
  var div = document.createElement('div')
  for (var key in global_t) {
    var val = global_t[key]
    var a = document.createElement('a');
    var linkText = document.createTextNode(key);
    a.appendChild(linkText);
    a.title = "Download " + key;
    a.href = "/api/down?id=" + id_elem + "&type=" + val;
    div.appendChild(a)
    div.appendChild(document.createElement('br'))
  }
  return div
}

function tableCreate(dat,elems,id) {
  var parent = document.getElementById(id);
  var tbl = document.createElement('table');
  var tbl_dat = JSON.parse(dat)
  tbl.style.width = '100%';
  tbl.setAttribute('border', '1');
  tbl.setAttribute('class','table is-bordered is-striped is-narrow is-hoverable is-fullwidth')
  tbl.id = "cert-table"
  var tbdy = document.createElement('tbody');
  var tr = document.createElement('tr');
    for (var j = 0; j < elems.length; j++) {
        var th = document.createElement('th');
        th.appendChild(document.createTextNode(elems[j]))
        tr.appendChild(th)
    }
        var th = document.createElement('th');
        th.appendChild(document.createTextNode("Download"))
        tr.appendChild(th)

    tbdy.appendChild(tr);
  for (var i = 0; i < tbl_dat.length; i++) {
    var tr = document.createElement('tr');
    for (var j = 0; j < elems.length; j++) {
        var td = document.createElement('td');
        td.appendChild(document.createTextNode(tbl_dat[i][elems[j]]))
        tr.appendChild(td)
    }
    // Custom Logic for downloads
        var td = document.createElement('td');
        var LinkText = create_link(i)
        td.appendChild(LinkText)
        tr.appendChild(td)

    tbdy.appendChild(tr);
  }
  tbl.appendChild(tbdy);
  parent.appendChild(tbl)
}

function api_to_table (url,elements,id) {
  const Http = new XMLHttpRequest();
  Http.open("GET", url);
  Http.send();
  Http.onloadend=(e)=>{
    console.log(Http.responseText)
    var elems = elements
    tableCreate(Http.responseText,elems,id)
  }
}

api_to_table("/api/list",["id","name","fingerprint","expires","key_exists"],"cert-container")
// I have modified the api_to_table function to add download link
// So, it is no more a generic function to create tables from API