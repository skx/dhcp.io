$(document).ready(function() {
    //hiding tab content except first one
    $(".tabContent").not(":first").hide();
    // adding Active class to first selected tab and show
    $("ul.tabs li:first").addClass("active").show();

    // Click event on tab
    $("ul.tabs li").click(function() {
    // Removing class of Active tab
    $("ul.tabs li.active").removeClass("active");
    // Adding Active class to Clicked tab
    $(this).addClass("active");
    // hiding all the tab contents
    $(".tabContent").hide();
    // showing the clicked tab's content using fading effect
    $($('a',this).attr("href")).fadeIn('slow');

    return false;
    });
});
