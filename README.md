## Azula

Azula is a strongly-typed compiled language, using an LLVM backend, with the following goals:
- Static typing
- Easy-to-read syntax
- Efficient execution

[Documentation](https://azula-lang.github.io/azula/#/)

### Origin

Azula started as a learning exercise through the [Writing a Interpreter in Go](https://interpreterbook.com) and [Writing a Compiler in Go](https://compilerbook.com) books by Thorsten Ball. As I reached the end of the compiler, rather than expanding the VM for Azula, I decided compiling to LLVM would make the language far more usable. Rather than attempting to change the version written in Go, I decided to rewrite Azula from scratch in Crystal.

### Goals

- ~~Tokenizer~~
- ~~Lexer~~
- ~~Parser~~
- Compiler
- Write documentation in code
- Compiler Optimization
- Standard Library
- Self-hosting compiler

## Compiling
Currently Azula only compiles to LLIR, therefore LLVM is required to run the compiled files.

```
crystal run src/azula.cr -- FILENAME
```

or if built
```
azula FILENAME
```

### Example Code

```
func fib(int x): int {
    if(x == 0 or x == 1) {
        return x;
    }
    return fib(x - 1) + fib(x - 2);
}

func main(): void {
    print(fib(15));
}
```
