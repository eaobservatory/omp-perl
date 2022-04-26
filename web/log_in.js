$(document).ready(function () {
    var log_in_panels = $('div.log_in_panel');
    log_in_panels.children('p').children('a').click(function () {
        log_in_panels.children('div').hide();
        $(this).parent().parent().children('div').show();
    });
    log_in_panels.children('p').children('a').first().click();
});
