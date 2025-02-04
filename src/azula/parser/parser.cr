require "../ast/*"
require "../token"
require "../lexer"
require "../types/*"
require "../errors/*"

# Add a prefix handler
macro register_prefix(token_type, method_name)
    @prefix_funcs[TokenType::{{token_type}}] = ->{ self.{{method_name}}.as(AST::Expression?)}
end

# Add an infix handler
macro register_infix(token_type, method_name)
    @infix_funcs[TokenType::{{token_type}}] = ->(exp: AST::Expression){ self.{{method_name}}(exp).as(AST::Expression?)}
end

# If peek token isn't token_type, return out of function
macro expect_peek_return(token_type)
    if !self.expect_peek TokenType::{{token_type}}
        return
    end
end

# If var is nil, return out of function
macro nil_return(var)
    if {{var}}.nil?
        return
    end
end

# Add the current_token to types, whether its a type or a string
macro type_or_literal
    type = Types::Type.type_from_string @current_token.literal
end

module Azula

    enum OperatorPrecedence
        LOWEST,
        COMPARISON,
        EQUALS,
        LESS_GREATER,
        SUM,
        PRODUCT,
        PREFIX,
        CALL,
        ACCESS,
    end

    Precedences = {
        TokenType::OR => OperatorPrecedence::COMPARISON,
        TokenType::AND => OperatorPrecedence::COMPARISON,
        TokenType::EQ => OperatorPrecedence::EQUALS,
        TokenType::NOT_EQ => OperatorPrecedence::EQUALS,
        TokenType::LT => OperatorPrecedence::LESS_GREATER,
        TokenType::LT_EQ => OperatorPrecedence::LESS_GREATER,
        TokenType::GT => OperatorPrecedence::LESS_GREATER,
        TokenType::GT_EQ => OperatorPrecedence::LESS_GREATER,
        TokenType::PLUS => OperatorPrecedence::SUM,
        TokenType::MINUS => OperatorPrecedence::SUM,
        TokenType::SLASH => OperatorPrecedence::PRODUCT,
        TokenType::ASTERISK => OperatorPrecedence::PRODUCT,
        TokenType::EXPONENT => OperatorPrecedence::PRODUCT,
        TokenType::MODULO => OperatorPrecedence::PRODUCT,
        TokenType::LBRACKET => OperatorPrecedence::CALL,
        TokenType::LBRACE => OperatorPrecedence::CALL,
        TokenType::LSQUARE => OperatorPrecedence::CALL,
        TokenType::DOT => OperatorPrecedence::ACCESS,
        TokenType::AMPERSAND => OperatorPrecedence::ACCESS,
    }

    class Parser

        @lexer : Lexer
        @errors : Array(String)
        @current_token : Token
        @peek_token : Token
        @infix_funcs : Hash(TokenType, Proc(AST::Expression, AST::Expression?))
        @prefix_funcs : Hash(TokenType, Proc(AST::Expression?))

        getter errors

        def initialize(@lexer)
            @errors = [] of String
            @current_token = @lexer.next_token
            @peek_token = @lexer.next_token

            @infix_funcs = {} of TokenType => Proc(AST::Expression, AST::Expression?)
            @prefix_funcs = {} of TokenType => Proc(AST::Expression?)

            register_prefix NUMBER, parse_number_literal
            register_prefix NULL, parse_null_literal
            register_prefix STRING, parse_string_literal
            register_prefix TRUE, parse_boolean_literal
            register_prefix FALSE, parse_boolean_literal
            register_prefix LBRACKET, parse_grouped_expression
            register_prefix IDENTIFIER, parse_identifier
            register_prefix NOT, parse_prefix_expression
            register_prefix MINUS, parse_prefix_expression
            register_prefix ASTERISK, parse_prefix_expression
            register_prefix AMPERSAND, parse_prefix_expression
            register_prefix LSQUARE, parse_array

            register_infix PLUS, parse_infix_expression
            register_infix MINUS, parse_infix_expression
            register_infix SLASH, parse_infix_expression
            register_infix ASTERISK, parse_infix_expression
            register_infix EXPONENT, parse_infix_expression
            register_infix MODULO, parse_infix_expression
            register_infix EQ, parse_infix_expression
            register_infix NOT_EQ, parse_infix_expression
            register_infix LT, parse_infix_expression
            register_infix LT_EQ, parse_infix_expression
            register_infix GT, parse_infix_expression
            register_infix GT_EQ, parse_infix_expression
            register_infix OR, parse_infix_expression
            register_infix AND, parse_infix_expression
            register_infix LBRACKET, parse_function_call_expression
            register_infix LBRACE, parse_struct_initialising
            register_infix LSQUARE, parse_array_access
            register_infix DOT, parse_access
        end

        # Advance current token pointer to the next token
        def next_token
            @current_token = @peek_token
            @peek_token = @lexer.next_token
        end

        # Parse an entire program
        def parse_program : AST::Program
            statements = [] of AST::Statement
            while @current_token.type != TokenType::EOF
                stmt = self.parse_statement
                if !stmt.nil?
                    statements << stmt
                else
                    return AST::Program.new statements
                end
                self.next_token
            end
            return AST::Program.new statements
        end

        # Parse a statement - something that has no return
        def parse_statement : AST::Statement?
            case @current_token.type
            when TokenType::TYPE
                return self.parse_assign_statement
            when TokenType::IDENTIFIER
                if @peek_token.type == TokenType::ASSIGN
                    return self.parse_assign_statement
                elsif @peek_token.type == TokenType::IDENTIFIER
                    return self.parse_assign_statement
                elsif @peek_token.type == TokenType::ASTERISK
                    return self.parse_assign_statement
                end
            when TokenType::RETURN
                return self.parse_return_statement
            when TokenType::CONTINUE
                return self.parse_continue_statement
            when TokenType::FUNCTION
                return self.parse_function_statement
            when TokenType::EXTERN
                return self.parse_external_function
            when TokenType::STRUCT
                return self.parse_struct
            when TokenType::IMPORT
                return self.parse_imports
            when TokenType::PACKAGE
                return self.parse_package
            when TokenType::IF
                return self.parse_if_statement true
            when TokenType::WHILE
                return self.parse_while_loop
            end
            case @peek_token.type
            when TokenType::COMMA
                return self.parse_assign_statement
            else
                return self.parse_expression_statement
            end

            ErrorManager.add_error(Error.new "unknown token " + @current_token.literal, @current_token.file, @current_token.linenumber, @current_token.charnumber)
            return nil
        end

        # Parse a block of statements
        def parse_block_statement : AST::Block?
            tok = @current_token
            stmts = [] of AST::Statement
            self.next_token

            while @current_token.type != TokenType::RBRACE && @current_token.type != TokenType::EOF
                if @current_token.type == TokenType::EOF
                    self.add_error "body has no close"
                    return
                end
                stmt = self.parse_statement
                if !stmt.nil?
                    stmts << stmt
                else
                    return
                end
                self.next_token
            end

            if @current_token.type != TokenType::RBRACE
                self.add_error "expected {, got EOF"
                return
            end

            return AST::Block.new tok, stmts
        end

        # Expect next token to be of a type, otherwise add new error
        def expect_peek(t : TokenType) : Bool
            if @peek_token.type == t
                self.next_token
                return true
            end
            if t == TokenType::SEMICOLON
                ErrorManager.add_error Error.new "expected semicolon", @current_token.file, @current_token.linenumber, @current_token.charnumber+1
                return false
            end
            ErrorManager.add_error Error.new "expected next token to be #{t}, got #{@peek_token.type} instead", @current_token.file, @current_token.linenumber, @current_token.charnumber+1
            return false
        end

        # Parse an expression - something that has a return value
        def parse_expression(precedence : OperatorPrecedence = OperatorPrecedence::LOWEST, close : TokenType = TokenType::SEMICOLON) : AST::Expression?
            prefix = @prefix_funcs.fetch @current_token.type, nil
            if prefix.nil?
                self.add_error "token #{@current_token.type} in wrong position, could not parse"
                return
            end

            left = prefix.call

            while @peek_token.type != close && precedence < self.token_precedence(@peek_token.type)
                infix = @infix_funcs.fetch @peek_token.type, nil
                nil_return infix

                self.next_token
                nil_return left
                left = infix.call left.not_nil!
            end

            return left
        end

        def parse_type : Types::Type?
            type = Types::Type.type_from_string @current_token.literal
            if @peek_token.type == TokenType::LBRACKET
                self.next_token
                self.next_token
                type.secondary_type = self.parse_type
                self.next_token
                #self.expect_peek TokenType::RBRACKET
            end
            return type
        end

        # Parse an assign statement, where value(s) are assigned to identifier(s)
        def parse_assign_statement : AST::Assign?
            t = @current_token
            idents = [] of (AST::TypedIdentifier | AST::Identifier)
            # type = parse_type
            if @peek_token.type == TokenType::IDENTIFIER || @peek_token.type == TokenType::ASTERISK || @peek_token.type == TokenType::LBRACKET
                ident = parse_typed_identifier
            else
                ident = parse_identifier
            end
            if ident.nil?
                ident = AST::Identifier.new @current_token, @current_token.literal
            end

            idents << ident

            # Keep going until there are no more commas
            while @peek_token.type == TokenType::COMMA
                self.next_token
                self.next_token
                type = Types::Type.type_from_string @current_token.literal
                if @peek_token.type == TokenType::IDENTIFIER || @peek_token.type == TokenType::ASTERISK
                    ident = parse_typed_identifier
                else
                    ident = parse_identifier
                end
                if ident.nil?
                    return
                end

                idents << ident
            end

            expect_peek_return ASSIGN

            values = self.parse_expression_list TokenType::SEMICOLON
            nil_return values

            if !type.nil? && type.is_int
                size = 32
                if type.main_type == Types::TypeEnum::INT8
                    size = 8
                elsif type.main_type == Types::TypeEnum::INT16
                    size = 16
                elsif type.main_type == Types::TypeEnum::INT64
                    size = 64
                end
                values.size.times do |i|
                    if values[i].as?(AST::IntegerLiteral) != nil
                        (values[i].as(AST::IntegerLiteral)).size = size
                    end
                end
            end

            return AST::Assign.new t, idents, values.not_nil!
        end

        def parse_array : AST::ArrayExp?
            token = @current_token
            exp_list = self.parse_expression_list TokenType::RSQUARE
            nil_return exp_list

            return AST::ArrayExp.new token, Types::Type.new(Types::TypeEnum::ARRAY), exp_list
        end

        # Parse a typed identifier, eg. int x, string y
        def parse_typed_identifier : AST::TypedIdentifier?
            assign_token = @current_token
            type = self.parse_type

            if @peek_token.type == TokenType::ASTERISK
                self.next_token

                expect_peek_return IDENTIFIER

                ident = AST::TypedIdentifier.new @current_token, @current_token.literal, Types::Type.new(Types::TypeEnum::POINTER, type)
                return ident
            end

            expect_peek_return IDENTIFIER

            return AST::TypedIdentifier.new @current_token, @current_token.literal, type
        end

        # Parse a string literal, eg. "hello world"
        def parse_string_literal : AST::StringLiteral
            return AST::StringLiteral.new @current_token, @current_token.literal
        end

        # Parse a number literal and convert it to either an int or float
        def parse_number_literal : (AST::IntegerLiteral? | AST::FloatLiteral?)
            # Check if there's a decimal point, if so it is a float
            if @peek_token.type == TokenType::DOT
                first = @current_token
                next_token
                next_token
                second = @current_token
                val = "#{first.literal}.#{second.literal}".to_f32
                if !val.nil?
                    return AST::FloatLiteral.new first, val
                end
                self.add_error "could not parse float"
                return
            end
            val = @current_token.literal.to_i
            if val.nil?
                self.add_error "could not parse integer"
            end
            return AST::IntegerLiteral.new @current_token, val
        end

        # Parse a boolean literal, either true or false
        def parse_boolean_literal : AST::BooleanLiteral
            return AST::BooleanLiteral.new @current_token, @current_token.type == TokenType::TRUE
        end

        # Parse a null literal
        def parse_null_literal : AST::NullLiteral?
            return AST::NullLiteral.new @current_token
        end

        # Parse a return statement, for returning a value from a function
        def parse_return_statement : AST::Return?
            tok = @current_token

            values = self.parse_expression_list TokenType::SEMICOLON
            if values.nil?
                self.add_error "error parsing return expression"
                return
            end

            return AST::Return.new tok, values
        end

        def parse_continue_statement : AST::Continue?
            tok = @current_token

            expect_peek_return SEMICOLON
            return AST::Continue.new tok
        end

        # Parse an infix expression, eg 5 + 5, 10 == 2
        def parse_infix_expression(left : AST::Expression) AST::Expression?
            tok = @current_token
            operator = @current_token.literal
            
            precedence = token_precedence tok.type
            self.next_token
            right = parse_expression precedence
            nil_return right

            return AST::Infix.new tok, left, operator, right.not_nil!
        end

        # Parse a prefix expression, eg. !true, -5
        def parse_prefix_expression : AST::Expression?
            cur_token = @current_token
            self.next_token
            exp = self.parse_expression OperatorPrecedence::PREFIX
            if exp.nil?
                return nil
            end
            return Azula::AST::Prefix.new cur_token, cur_token.literal, exp.not_nil!
        end

        # Parse a list of expressions, separated by a comma
        def parse_expression_list(last : TokenType) Array(AST::Expression)
            exps = [] of AST::Expression

            if @peek_token.type == last
                self.next_token
                return exps
            end

            self.next_token
            exp = self.parse_expression
            if !exp.nil?
                exps << exp
            end

            while @peek_token.type == TokenType::COMMA
                self.next_token
                self.next_token
                exp = self.parse_expression
                if !exp.nil?
                    exps << exp
                end
            end

            if !expect_peek last
                return
            end

            return exps
        end

        # Parse an identifier eg. x, y, my_func
        def parse_identifier : AST::Identifier?
            return AST::Identifier.new @current_token, @current_token.literal
        end

        # Parse a function definition
        def parse_function_statement : AST::Function?
            tok = @current_token
            self.next_token
            name = AST::Identifier.new @current_token, @current_token.literal

            expect_peek_return LBRACKET

            params = self.parse_function_parameters
            nil_return params

            expect_peek_return COLON

            self.next_token

            return_type = self.parse_function_return_type
            nil_return return_type

            expect_peek_return LBRACE

            body = self.parse_block_statement
            nil_return body

            return AST::Function.new tok, name, params, return_type, body.not_nil!
        end

        # Parse an external function
        def parse_external_function : AST::ExternFunction?
            tok = @current_token
            self.next_token
            self.next_token
            name = AST::Identifier.new @current_token, @current_token.literal

            expect_peek_return LBRACKET

            params = self.parse_function_parameters
            nil_return params

            expect_peek_return COLON

            self.next_token

            return_type = self.parse_function_return_type
            nil_return return_type

            expect_peek_return SEMICOLON

            return AST::ExternFunction.new tok, name, params, return_type
        end

        # Parse the parameters of a function, returning a list of TypedIdentifiers
        def parse_function_parameters : Array(AST::TypedIdentifier)?
            idents = [] of AST::TypedIdentifier

            if @peek_token.type == TokenType::RBRACKET
                self.next_token
                return idents
            end

            self.next_token

            ident = self.parse_typed_identifier
            nil_return ident
            idents << ident

            # Keep going until there is no comma
            while @peek_token.type == TokenType::COMMA
                self.next_token
                self.next_token
                ident = self.parse_typed_identifier
                nil_return ident
                idents << ident
            end

            expect_peek_return RBRACKET

            return idents
        end

        # Parse the return type of a function
        def parse_function_return_type : Types::Type?
            return Types::Type.type_from_string @current_token.literal
        end

        # Parse a grouped expression, eg. (5 + 2)
        def parse_grouped_expression : AST::Expression?
            self.next_token
            exp = self.parse_expression
            expect_peek_return RBRACKET

            return exp
        end

        # Parse a function call, eg. my_func(5)
        def parse_function_call_expression(function : AST::Expression) AST::Expression?
            function = function.as?(AST::Identifier)
            nil_return function
            tok = @current_token
            args = self.parse_expression_list TokenType::RBRACKET
            if args.nil?
                self.add_error "invalid expressions in function call"
                return
            end
            nil_return args

            return AST::FunctionCall.new tok, function.as(AST::Identifier), args
        end

        def parse_array_access(array : AST::Expression) AST::Expression?
            token = @current_token
            self.next_token
            index = self.parse_expression(OperatorPrecedence::LOWEST, TokenType::RSQUARE)
            self.next_token
            if index.nil?
                self.add_error "index is invalid in array indexing"
                return
            end

            return AST::ArrayAccess.new token, array, index
        end

        # Parse an expression statement, which is just an expression with nothing being done with that value
        def parse_expression_statement : AST::ExpressionStatement?
            tok = @current_token
            exp = self.parse_expression
            nil_return exp
            expect_peek_return SEMICOLON

            return AST::ExpressionStatement.new tok, exp.not_nil!
        end

        # Parse a struct definition
        def parse_struct : AST::Struct?
            tok = @current_token
            self.next_token
            name = AST::Identifier.new @current_token, @current_token.literal

            fields = [] of AST::TypedIdentifier
            expect_peek_return LBRACE

            while @peek_token.type != TokenType::RBRACE
                self.next_token
                exp = self.parse_typed_identifier
                if exp.nil?
                    self.add_error "invalid typed identifier declaration"
                    return
                end
                fields << exp.not_nil!
                if @peek_token.type != TokenType::COMMA
                    break
                end
                self.next_token
            end

            expect_peek_return RBRACE

            return AST::Struct.new tok, name, fields
        end

        # Parse the initialising of a struct, eg. Person{5, 2}
        def parse_struct_initialising(struct_ident : AST::Expression) : AST::Expression?
            struct_ident = struct_ident.as?(AST::Identifier)
            nil_return struct_ident
            tok = @current_token
            args = self.parse_expression_list TokenType::RBRACE
            if args.nil?
                self.add_error "invalid struct fields"
                return
            end

            return AST::StructInitialise.new tok, struct_ident, args
        end

        def parse_imports : AST::Import?
            tok = @current_token
            imports = [] of String
            expect_peek_return LBRACE

            while @peek_token.type != TokenType::RBRACE
                self.next_token
                str = self.parse_string_literal.value
                imports << str
            end

            self.next_token

            return AST::Import.new tok, imports
        end

        def parse_package : AST::Package?
            tok = @current_token
            self.next_token
            name = self.parse_string_literal.value

            expect_peek_return SEMICOLON

            return AST::Package.new tok, name
        end

        # Parse an if statement, checking for elseifs and elses
        def parse_if_statement(top_level : Bool) : AST::If?
            tok = @current_token
            expect_peek_return LBRACKET
            self.next_token
            
            # Parse if condition
            exp = self.parse_expression OperatorPrecedence::LOWEST, TokenType::RBRACKET
            if exp.nil?
                self.add_error "invalid if condition"
                return
            end

            expect_peek_return RBRACKET
            expect_peek_return LBRACE
            cond = self.parse_block_statement
            nil_return cond

            if !top_level
                return AST::If.new tok, exp.not_nil!, cond.not_nil!, [] of AST::If, nil
            end

            alts = [] of AST::If

            # While there are elseifs, keep checking for them
            while @peek_token.type == TokenType::ELSEIF
                self.next_token
                alt = self.parse_if_statement false
                nil_return alt
                alts << alt
            end

            alternative : AST::Block?

            # If there is an else block, parse it
            if @peek_token.type == TokenType::ELSE
                self.next_token
                expect_peek_return LBRACE
                alternative = self.parse_block_statement
                nil_return alternative
            end

            return AST::If.new tok, exp.not_nil!, cond.not_nil!, alts, alternative
        end

        # Parse a while loop
        def parse_while_loop : AST::While?
            tok = @current_token
            expect_peek_return LBRACKET
            self.next_token
            exp = self.parse_expression OperatorPrecedence::LOWEST, TokenType::RBRACKET
            nil_return exp

            expect_peek_return RBRACKET
            expect_peek_return LBRACE
            body = self.parse_block_statement
            nil_return body

            return AST::While.new tok, exp, body
        end

        def parse_access(s : AST::Expression) : AST::Access?
            tok = @current_token
            self.next_token
            exp = self.parse_expression
            if exp.nil?
                return
            end

            return AST::Access.new tok, s, exp
        end

        # Returns the operator precedence of a token
        def token_precedence(type : TokenType) OperatorPrecedence
            pre = Precedences.fetch type, nil
            if pre.nil?
                return OperatorPrecedence::LOWEST
            end
            return pre
        end

        # Add an error to the errors list
        def add_error(error : String)
            ErrorManager.add_error Error.new error, @current_token.file, @current_token.linenumber, @current_token.charnumber
        end

    end
end