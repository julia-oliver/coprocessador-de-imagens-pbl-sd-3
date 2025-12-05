build:
	@gcc -c main.c -std=c99 -o main.o
	@gcc -c api.s -o api.o
	@gcc api.o main.o -o pixel_test -lm

run:
	sudo ./pixel_test

help:
	@echo ""
	@echo "📘 Comandos disponíveis:"
	@echo "  make build  - Compila o programa (gera pixel_test)"
	@echo "  make run    - Executa o programa (usa sudo)"
	@echo "  make help   - Mostra esta mensagem de ajuda"
	@echo ""

