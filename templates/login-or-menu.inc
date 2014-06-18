<!-- tmpl_if name='username' -->
<div id="container">
  <span style="font-size:20px;"><a href="/"><!-- tmpl_var name='uc_zone' --></a> - Fast and Reliable Dynamic-DNS</span>
  <div id="loginContainer">
    <a href="/logout/" class="Button"><span>Logout</span><em></em></a>
    <a href="/faq/" class="Button"><span>FAQ</span><em></em></a>
  </div>
</div>
<!-- tmpl_else -->
<div id="container">
  <span style="font-size:20px;"><a href="/"><!-- tmpl_var name='uc_zone' --></a> - Fast and Reliable Dynamic-DNS</span>
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
        <span><a href="/create/">Create an account</a></span>
      </form>
    </div>
  </div>
  <a href="/faq/" class="Button"><span>FAQ</span><em></em></a>
</div>
<!-- /tmpl_if -->
