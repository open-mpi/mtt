function popup_named_window(width,height,title,script,content,style) {
    newwindow2=window.open('','name','height=' + height + ',width=' + width + ',scrollbars=yes');
    var tmp = newwindow2.document;
    tmp.write('<html><head>' + script + '<title>' + title + '</title></head>');
    tmp.write('<body ' + style + '><form id=adv name=adv method=get>' + content + '</form></body></html>');
    tmp.close();
}
 
function popup_nameless_html_window(width,height,title,script,content,style) {
    newwindow2=window.open('','','height=' + height + ',width=' + width + ',scrollbars=yes');
    var tmp = newwindow2.document;
    tmp.write('<html><head>' + script + '<title>' + title + '</title></head>');
    tmp.write('<body ' + style + '><form id=adv name=adv method=get>' + content + '</form></body></html>');
    tmp.close();
}
 
function popup_nameless_text_window(width,height,content) {
    newwindow2=window.open('','','height=' + height + ',width=' + width + ',scrollbars=yes');
    var tmp = newwindow2.document;
    tmp.write(content);
    tmp.close();
}
 
function OpenPermalinkConfirmation(date) {
    var link = location.href;
 
    link += '&text_start_timestamp=' + date;
    link += '&make_redir=1';
 
    open(link, 'Tiny link', 'resizable=yes, toolbar=no, location=no, directories=no, status=no, menubar=no, scrollbars=no, width=500, height=150');
}
 
function OpenWindowForMTTFailureDB() {
    var link = location.href;
    link += '&show_failure_db=1';
    open(link, 'MTT Failures Database', 'resizable=yes, toolbar=no, location=no, directories=no, status=no, menubar=no, scrollbars=no, width=500, height=500');
    }

function StartOver() {
    document.report.text_start_timestamp.value = 'past 24 hours';
    document.report.text_http_username.value = 'all';
    document.report.text_local_username.value = 'all';
    document.report.text_platform_name.value = 'all';
    document.report.text_platform_hardware.value = 'all';
    document.report.text_os_name.value = 'all';
    document.report.text_mpi_name.value = 'all';
    document.report.text_mpi_version.value = 'all';
    document.report.text_show.value = 'Array';
    document.report.text_phase.value = 'all_phases';
    document.report.text_dev.value = 'Array';
}
