<cfcomponent output="yes">
	<cfoutput>
	<cffunction name="index" access="remote">
		<cfscript>
		var db=0;
		var q=0;
		var local={};
		</cfscript>
        <h1>db.cfc Example Code</h1>
        <h2>QueryNew() example data stored in request.qTemp so db.cfc can access it.</h2>
        <cfscript>
		// Let's build a query so we don't need a database to test db.cfc
		request.qTemp=querynew("firstName,lastName","varchar,varchar", 
		[ 
			["John","Doe"],
			["Jane","Smith"],
			["Jill","Scott"],
			["Ivy","Lane"]
		]);
		</cfscript>
        <cfdump var="#request.qTemp#">
        
        <hr />
        <h2>Query of query using cfquery tag</h2>
        <cfquery dbtype="query" name="local.qResult">
        select * from request.qTemp where lastName=<cfqueryparam value="Doe" cfsqltype="cf_sql_varchar">
        </cfquery>
        <cfdump var="#local.qResult#">
        <hr />
        <h2>Query of query using db.cfc</h2>
        <cfscript>
		db=createobject("db");
		db.init({
			dbtype:"query",
			verifyQueriesEnabled:true,
			identifierQuoteCharacter:'' // this is usually a backtick, but query of queries doesn't support that character for table names.
		});
		q=db.newQuery();
		q.sql="select * from "&q.table("qTemp", "request")&" where lastName="&q.param("Doe", "cf_sql_varchar");
		local.qResult=q.execute("qResult");
		writedump(local.qResult);
		</cfscript>
        
        <hr />
		<h2>Example of running a sql filter on the query before it is executed.</h2>
        <p>The function, "parsedSQLHelloWorld", adds " where lastName='smith' " to the sql statement at the beginning of q.execute(). This causes local.qResult to only contain "Jane Smith".</p>
        <cfscript>
		q=db.newQuery({parseSQLFunctionStruct:{parsedSQLHelloWorld:this.parsedSQLHelloWorld}});
		q.sql="select * from "&q.table('qTemp','request');
		local.qResult=q.execute("qResult");
		writedump(local.qResult);
		q=db.newQuery({parseSQLFunctionStruct:{}});
		</cfscript>
        
        
        <hr />
		<h2>db.cfc throws exception when string literal or number isn't passed in with db.param() or db.trustedSQL().</h2>
        <p>The following code will throw an exception because 'Doe' is a string literal.  It must be passed in with q.param('Doe') or q.trustedSQL('Doe').
        <cfscript>
		q.sql="select * from "&q.table("qTemp", "request")&" where lastName='Doe'";
		try{
			local.qResult=q.execute("qResult");
		}catch(Any e){
			writeoutput("<p><strong>Error Message:</strong>"&e.message&'</p>');
		}
		</cfscript>
        
        
        <hr />
		<h2>Exception because string literal wasn't passed in with q.table().</h2>
        <p>The following code will throw an exception because request.qTemp was not passed in with q.table('qTemp', 'result').
        <cfscript>
		q.sql="select * from request.qTemp";
		try{
			local.qResult=q.execute("qResult");
		}catch(Any e){
			writeoutput("<p><strong>Error Message:</strong>"&e.message&'</p>');
		}
		</cfscript>
        
    </cffunction>
    
    <cffunction name="parsedSQLHelloWorld">
        <cfargument name="parsedSQLStruct">
        <cfscript>
        arguments.parsedSQLStruct.sql&=(" where lastName='Smith' ");
        return arguments.parsedSQLStruct;
        </cfscript>
    </cffunction>
    </cfoutput>
</cfcomponent>