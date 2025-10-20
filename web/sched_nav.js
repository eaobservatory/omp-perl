$(document).ready(function () {
    $('a#today').click(function () {
        var date = new Date();
        var date_str = date.toISOString().substr(0, 10);

        var element = $('#night_' + date_str);
        if (element.length) {
            $('table.schedule').find('tr').css('background', 'none');
            element.css('background', '#FF0');
            $('html, body').animate({scrollTop: element.offset().top}, 500);
        }
    });
});
