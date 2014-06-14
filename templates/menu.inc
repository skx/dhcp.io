<!-- tmpl_if name='username' -->
          <h2>User Menu</h2>
          <ul>
            <li><a href="/logout">Logout</a></li>
          </ul>
<!-- tmpl_else -->
          <h2>User Menu</h2>
          <form method="POST" action="/cgi-bin/index.cgi">
            <input type="hidden" name="mode" value="login">
            <table>
              <tr><td>Username</td>
                <td> <input type="text" name="lname"></td>
              </tr>
              <tr><td>Password</td>
                <td> <input type="password" name="lpass"></td>
              </tr>
              <tr><td></td><td align="right"><input type="submit" name="submit" value="Login"></td></tr>
            </table>
          </form>
<!-- /tmpl_if -->