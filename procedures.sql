 /****** Object:  Stored Procedure dbo.organiza_fichas_atend ******/
CREATE PROCEDURE organiza_fichas_atend
  @par_atendimento integer,
  @par_tempo_distribui_fichas dateTime, 
  @par_QtdConvXComum integer,
  @par_QtdComumXConv integer,
  @par_TempoLimiteFichaEmEspera datetime
AS
begin  
  declare @Posicao integer 
  declare @Ordem integer
  declare @NumeroAtendimento integer
  declare @HrVoltaFicha datetime 
  declare @DataAgenda datetime
  declare @HoraAgenda datetime  
  declare @TempoAvisoAgenda datetime
  declare @HrAgenda datetime 
  declare @QtdeConvenios integer 
  declare @QtdeComuns integer
  declare @HrInicioEspera datetime

  if @par_atendimento > 0 
    update atendimento set ordem_ficha=1 where c_atendimento=@par_atendimento 
  else
  begin
    declare Convenios_Cursor cursor local static for
    select c_atendimento
    from atendimento
    where em_uso_operador='N'  and
          tp_ficha='V' and (espera is null or (espera<>'T'  and espera<>'E' ))
    order by c_atendimento
    
    declare ClientesComuns_Cursor cursor local static for
    select c_atendimento
    from atendimento
    where em_uso_operador='N'  and
         (tp_ficha='C' or tp_ficha='R') and (espera is null or (espera<>'T'  and espera<>'E' ))
    order by c_atendimento

    declare ClientesAgendados_Cursor cursor local static for
    select c_atendimento,dt_agenda,hr_agenda,tempo_aviso_agenda
    from atendimento
    where em_uso_operador='N'  and
          tp_ficha='A'   and (espera is null or (espera<>'T'  and espera<>'E' ))
    order by hr_agenda

    declare ClientesEmEspera_Cursor cursor local static for
    select c_atendimento,hr_volta_ficha,hr_inicio_espera
    from atendimento
    where em_uso_operador='N'  and
          espera='E' or  espera='T' 
    order by hr_volta_ficha

    declare ClientesEmAtendOperador_Cursor cursor local static for
    select c_atendimento
    from atendimento
    where em_uso_operador='S' 
    order by posicao_ficha

    open ClientesAgendados_Cursor
    open ClientesEmEspera_Cursor
    open ClientesEmAtendOperador_Cursor

    open Convenios_Cursor
    select @QtdeConvenios=@@CURSOR_ROWS

    open ClientesComuns_Cursor
    select @QtdeComuns=@@CURSOR_ROWS

    set @Posicao = 1 /*contador para controlar a posicao da ficha Conv X Comum*/      
    set @Ordem   = 2 /*ordem sequencial que sera gravado na tabela de atendimentos*/

    /*ordena as fichas que estão sendo atendidas pelo operador*/
    fetch ClientesEmAtendOperador_Cursor into @NumeroAtendimento
    while @@FETCH_STATUS=0
    begin
      update atendimento set ordem_ficha=@Ordem where c_atendimento=@NumeroAtendimento

      fetch ClientesEmAtendOperador_Cursor into @NumeroAtendimento
    end       

    /*Ordena fichas da espera*/    
    fetch ClientesEmEspera_Cursor into @NumeroAtendimento,@HrVoltaFicha,@HrInicioEspera
    while @@FETCH_STATUS=0
    begin
      if (getdate() >= @HrVoltaFicha) or (getdate() >= @HrInicioEspera+@par_TempoLimiteFichaEmEspera)
      begin
        update atendimento set ordem_ficha=@Ordem where c_atendimento=@NumeroAtendimento
        set @Ordem=@Ordem + 1
      end
      else
        update atendimento set ordem_ficha=10000 where c_atendimento=@NumeroAtendimento

      fetch ClientesEmEspera_Cursor into @NumeroAtendimento,@HrVoltaFicha,@HrInicioEspera 
    end       

    /*Ordena fichas de agendamento*/
    fetch ClientesAgendados_Cursor into @NumeroAtendimento,@DataAgenda,@HoraAgenda,@TempoAvisoAgenda
    while @@FETCH_STATUS=0
    begin
      Set @HrAgenda=@DataAgenda+(@HoraAgenda-@TempoAvisoAgenda)

      if getdate() >= @HrAgenda 
      begin
        update atendimento set ordem_ficha=@Ordem where c_atendimento=@NumeroAtendimento
        set @Ordem=@Ordem + 1
      end
      else
        update atendimento set ordem_ficha=11000 where c_atendimento=@NumeroAtendimento

      fetch ClientesAgendados_Cursor into @NumeroAtendimento,@DataAgenda,@HoraAgenda,@TempoAvisoAgenda
    end       

    while (@QtdeConvenios <= 0) and (@QtdeComuns <= 0) 
    begin
      if (@QtdeComuns=0) or ((@Posicao <= @par_QtdConvXComum) and (@QtdeConvenios > 0))
      begin
        update atendimento set ordem_ficha=@Ordem where c_atendimento=@NumeroAtendimento
        fetch Convenios_Cursor into @NumeroAtendimento
      end
      else
      begin
        if (@QtdeConvenios=0) or ((@Posicao <= @par_QtdComumXConv) and (@QtdeComuns > 0))
        begin
          update atendimento set ordem_ficha=@Ordem where c_atendimento=@NumeroAtendimento
          fetch ClientesComuns_Cursor into @NumeroAtendimento 
        end
      end 
    end
  end
  close ClientesAgendados_Cursor
  close ClientesEmEspera_Cursor
  close ClientesEmAtendOperador_Cursor
  close Convenios_Cursor
  close ClientesComuns_Cursor

  deallocate ClientesAgendados_Cursor
  deallocate ClientesEmEspera_Cursor
  deallocate ClientesEmAtendOperador_Cursor
  deallocate Convenios_Cursor
  deallocate ClientesComuns_Cursor
end


/****** Object:  Stored Procedure dbo.filtra_rt_ficha  ******/
CREATE PROCEDURE filtra_rt_ficha
  @NroAtendimento integer,
  @RtTitular integer, 
  @RtAtivo integer,
  @RtPermitidoParaFicha char(01) OUTPUT
AS
begin
  declare @QtdeEspecificFicha integer
  declare @CodEspecificFicha integer 
  declare @EspecificLocalizada char(01)
  declare @NroRt                      integer 

  declare EspecificFicha_Cursor cursor local static for
  select a.c_especific_carro
  from especific_atend a, especific_carro b
  where a.c_atendimento=@NroAtendimento          and
        a.c_especific_carro=b.c_especific_carro and
        b.tipo_caracteristica<>'C'

  open EspecificFicha_Cursor

  set @QtdeEspecificFicha=@@CURSOR_ROWS
  set @EspecificLocalizada='T'

  fetch EspecificFicha_Cursor into @CodEspecificFicha
  while (@QtdeEspecificFicha > 0) and (@EspecificLocalizada='T')/*@QtdeEspecificFicha <= 0*/
  begin
    set @NroRt=(select n_rt from rt where rt_inativo='F' and c_rt=@RtAtivo)
    
    declare EspecificRtVeiculo cursor local dynamic for
    select n_rt,c_especific_carro 
    from rt_especific_carro
    where n_rt=@NroRt and c_especific_carro=@CodEspecificFicha
    union all
    select a.c_rt_titular, b.c_especific_carro
    from veiculos a, ve_especific_carro b
    where c_rt_titular=@RtTitular  and
          b.placa=a.placa  and c_especific_carro=@CodEspecificFicha

    open EspecificRtVeiculo
    if @@CURSOR_ROWS=0 
      set @EspecificLocalizada='F'    

    fetch EspecificFicha_Cursor into @CodEspecificFicha
    set @QtdeEspecificFicha=@QtdeEspecificFicha - 1

    close EspecificRtVeiculo
    deallocate EspecificRtVeiculo
  end       
  set @RtPermitidoParaFicha=@EspecificLocalizada

  close EspecificFicha_Cursor
  deallocate EspecificFicha_Cursor
end



/****** Object:  Stored Procedure dbo.distribui_rts ******/
CREATE procedure distribui_rts
as
begin
  declare @NroFichaAtendimentoAtual integer
  declare @NroFichaAtendimento integer
  declare @TpFicha char(01)
  declare @DistribuicaoOk char(01)
  declare @PosicaoFicha integer
  declare @Distribuido char(01)
  declare @EmUsoFicha char(01)
  declare @RtTitular integer
  declare @RtAtivo integer
  declare @ReferenciaFicha char(03)
  declare @ReferenciaCadastrada char(03)
  declare @RtEmUsoFicha integer 
  declare @RtEspecificFicha char(01) 

  SET NOCOUNT ON
  update atendimento set c_rt=0,c_refe_prefeitura=''
  update referencias_rt set distribuido='N'
  
  declare Atendimento_Cursor cursor local static for
  select a.c_atendimento,a.tp_ficha,a.posicao_ficha,b.c_refe_prefeitura 
  from atendimento a, referencias_atend b
  where  a.cancelamento<>'C' and
         a.tp_ficha<>'R'     and
         a.c_atendimento=b.c_atendimento 
  order by a.ordem_ficha,a.c_atendimento,b.c_refe_atend

  open Atendimento_Cursor
  fetch Atendimento_Cursor into @NroFichaAtendimentoAtual,@TpFicha,@PosicaoFicha,@ReferenciaFicha
  while @@FETCH_STATUS=0
  begin
    set @DistribuicaoOk='F'
    set @NroFichaAtendimento=@NroFichaAtendimentoAtual

    while (@@FETCH_STATUS=0) and (@NroFichaAtendimento=@NroFichaAtendimentoAtual)
    begin
      if @DistribuicaoOk='F'
      begin
        declare Referencias_rt_Cursor cursor local static for
        select c_rt,c_rt_ativo,c_refe_prefeitura,em_uso_ficha,distribuido
        from referencias_rt   
        where c_refe_prefeitura=@ReferenciaFicha
        order by c_refe_prefeitura,prioridade,hr_cadastro

        open Referencias_rt_Cursor
        fetch Referencias_rt_Cursor into @RtTitular,@RtAtivo,@ReferenciaCadastrada,@RtEmUsoFicha,@Distribuido
        while (@@FETCH_STATUS=0) and (@ReferenciaCadastrada=@ReferenciaFicha) and (@DistribuicaoOk='F')
        begin         
          exec filtra_rt_ficha @NroFichaAtendimentoAtual,@RtTitular,@RtAtivo,@RtEspecificFicha output
          if (@Distribuido='N') and (@RtEspecificFicha='T') and (@RtEmUsoFicha=0 or @RtEmUsoFicha<>@PosicaoFicha)
          begin
            /*atualiza o flag de distribudo na tabela de referencias_rt*/
            update referencias_rt set distribuido='S' where c_rt_ativo=@RtAtivo
            
            /*atualiza a tabela de atendimentos com o RT e a REFERENCIA*/
            update atendimento set c_rt=@RtAtivo,c_refe_prefeitura=@ReferenciaCadastrada,distribuido='S'
            where c_atendimento=@NroFichaAtendimentoAtual

            set @DistribuicaoOk='T' 
          end
          fetch Referencias_rt_Cursor into @RtTitular,@RtAtivo,@ReferenciaCadastrada,@RtEmUsoFicha,@Distribuido
        end
        close Referencias_rt_Cursor
        deallocate Referencias_rt_Cursor
      end
      fetch Atendimento_Cursor into @NroFichaAtendimentoAtual,@TpFicha,@PosicaoFicha,@ReferenciaFicha
    end
  end
  SET NOCOUNT OFF

  close Atendimento_Cursor
  deallocate Atendimento_Cursor
end
