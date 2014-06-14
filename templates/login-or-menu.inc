<!-- tmpl_if name='username' -->
             <div id="container">
	<span style="font-size:20px;"><a href="/">DHCP.io</a> - Free Dynamic DNS</span>
            <div id="loginContainer">
                <a href="/logout/" class="Button"><span>Logout</span><em></em></a>
            </div>
        </div>
<!-- tmpl_else -->
        <div id="container">
	<span style="font-size:20px;"><a href="/">DHCP.io</a> - Free Dynamic DNS</span>

            <!-- Login Starts Here -->
            <div id="loginContainer">
                <a href="/login/" id="loginButton"><span>Login</span><em></em></a>
                <div style="clear:both"></div>
                <div id="loginBox">
                    <form id="loginForm" method="POST" action="/login/">
                    <input type="hidden" name="mode" value="login">
                        <fieldset id="body">
                            <fieldset>
                                <label for="lname">Login</label>
                                <input type="text" name="lname" id="lname" />
                            </fieldset>
                            <fieldset>
                                <label for="lpass">Password</label>
                                <input type="password" name="lpass" id="lpass" />
                            </fieldset>
                            <input type="submit" name="login" id="login" value="Sign in" />
                        </fieldset>
                    </form>
                </div>
            </div>
            <!-- Login Ends Here -->
        </div>
<!-- /tmpl_if -->