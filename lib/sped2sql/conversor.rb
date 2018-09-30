require "pry"
# -*- encoding: utf-8 -*-
module SPED2SQL
  class Conversor < Pipeline::Base
    include Layout

    attr_reader :fonte, :template, :saida, :memoria, :options, :errors

    def initialize(fonte, template, options = {})
      @fonte      = fonte
      @template   = template.is_a?(Symbol) ? Mapa.arquivo_template(template) : template
      @saida      = []
      @memoria    = Hash.new { |k, v| k[v] = [] }
      @options    = options
      @errors     = []

      valida_arquivo(@fonte)
      valida_arquivo(@template)

      tasks = if options[:tasks].is_a?(Array)
                options[:tasks]
              elsif options[:tasks] == :vazio
                []
              else
                [Pipeline::NormalizaSQL, Pipeline::AddHash]
              end

      super(tasks)
    end

    def converter!
      mapa  = Mapa.carrega!(@template)
      dados = IO.read(fonte, encoding: 'ISO-8859-1').gsub("'", '"')
      row_count = 0

      CSV.parse(dados, col_sep: '|', quote_char: "'") do |row|
        row_count += 1
        # pula linha se o registro nao existe no mapa
        next unless mapa.has_key?(row[1])

        begin
          # O primeiro e o ultimo item de uma linha no SPED sempre eh nulo
          linha = row.clone[1..-2]

          # Executa o pipe
          pipe = execute({ original: linha,
                           final:    linha,
                           mapa:     mapa,
                           memoria:  @memoria,
                           saida:    @saida,
                           options:  @options })

          @saida << pipe[:final]
          @memoria[linha.first] << pipe[:final]
          puts "Processando #{row_count} - #{pipe[:final]}"

          # Para um arquivo completo do SPED, 9999 eh o ultimo registro.
          # termina a leitura do arquivo no registro 9999 evitando ler
          # linhas em branco ou assinatura digital
          break if linha[0].to_i == 9999

        # Guarda em @errors as mensagens e pula para a próxima linha
        rescue => e
          binding.pry
          @errors << "#{row_count} - #{e.message}"
        end
      end
    end

    def to_sql
      SQL::Parser.to_sql(@saida, @options[:db] || {})
    end

    private

    def valida_arquivo(file)
      fail(ArgumentError, "Arquivo inexistente: #{file}") unless File.exist?(file)
    end
  end
end
