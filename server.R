options(shiny.maxRequestSize = 1000 * 1024 ^ 2)

library(ggplot2)
library(data.table)


shinyServer(function(input, output, session) {

#-------------------------------- Table reading ---------------------------
  # variable stored data (raw and filtered)
  values <- reactiveValues(df_data = NULL, sel.table = NULL, length.cont = 0)
    
  # read data 
  observeEvent(input$file, 
               {if (is.null(input$file$datapath) == FALSE) {
                 progress <- Progress$new(session)
                 on.exit(progress$close())
                 progress$set(message = 'Reading table in progress ...')
                 values$df_data <- NULL
                 values$length.cont <- length(scan(input$file$datapath, what = "character", nmax = 2))
                 if ( values$length.cont > 0) {
                   values$df_data <- fread(input$file$datapath,  h = T)
                 }
               }
               }
  )
  
  # check if  user read data
  messageToUser <- function(val_1, val_2) {
    if (val_1 == 0  & is.null(val_2) == TRUE) {
      "Please read file with your data"
      } else if ( val_1 == 0 & is.null(val_2) == FALSE) {
        "Empty file was read. Please read file with data"
      } else (NULL)
    }
  
   check.data <- reactive({
     validate(
       messageToUser(values$length.cont, input$file$datapath)
     )
   })
        
  # render button box 
   output$factorcheckboxes <- renderUI({
     check.data()
     factornames <- colnames(values$df_data)
     radioButtons(inputId = "variable",
                  label = "Select one from avaliable variables:", 
                  choices = factornames, 
                  selected = "all", 
                  inline = FALSE 
     )
   })
  
  check.variable <- reactive({
    validate(
      need(length(input$variable) > 0, "")
    )
  })
  
  # render selection of variables to remove
  output$factorselect <- renderUI({ 
    check.variable()
    levelnames <- unique(values$df_data[[input$variable]])
    if (is.numeric(levelnames) == TRUE & length(levelnames > 2)) {
      maximum <- max(levelnames)
      minimum <- min(levelnames)
      sliderInput(inputId = "factors.slider", 
                  label = "Select range of removed values:", 
                  value = c(minimum, maximum),
                  min = ceiling(minimum), 
                  max = floor(maximum), 
                  step = ifelse(maximum - minimum < 10, 0.2, 1), 
                  animate = F,
                  round = TRUE)
    } else {
      selectInput(inputId = "factors", 
                  label = "Select group of variables to remove:", 
                  choices = levelnames, 
                  multiple = T
      )
    }
  })
  
  # output$cleardata <- renderUI({
  #   check.variable()
  #   actionButton(inputId = "clear", label = "Clear data")
  # })
  # 
  # observeEvent(input$clear, {
  #   values$df_data = NULL
  #   output$cleardata <- removeUI(selector = "clear")
  #   }
  #   )
  
  # if the user select values to remove, this function filter out this selected rows
  observeEvent(input$factors, {
    if ( is.null(input$factors)) {
      values$sel.table = NULL
    } else {
      values$sel.table <- values$df_data[-which(values$df_data[[input$variable]] %in% input$factors), ]
    }
    })
  
  observeEvent(input$factors.slider, {
    if (is.null(input$factors.slider) == FALSE) {
      values$sel.table <- values$df_data[which(values$df_data[[input$variable]] > input$factors.slider[1] &
                                                  values$df_data[[input$variable]] < input$factors.slider[2]), ]
    }
  })
  
  # rendering table, if some values are excluded by user changed table is rendered
  output$table = renderDataTable({
    if ((is.null(input$factors) | length(input$factors) == 0) & is.null(input$factors.slider) ) {
      values$df_data
    } else {
      values$sel.table 
    }
  })
  
# -------------------------- UI rendering - update select input - PLOTS ----------------------

  # render new variables names in plot tabs
  observe({
    #check.data()
    updateSelectInput(session, "variable.x", choices = colnames(values$df_data))
    updateSelectInput(session, "variable.y",  choices = colnames(values$df_data))
    updateSelectInput(session, "variable.color", choices = c("NULL",colnames(values$df_data)))
  })

#-------------------------------------- PLOTS -------------------------------------------
  
  # crete reactive values to store readed data
  plot.dat <- reactiveValues(main = NULL, layer = NULL)
  
  # define input to render plot
  observeEvent(input$plottype, {
    # define general layout of plot
    plot.dat$main <- ggplot(data = values$df_data, 
                            mapping = aes(x = values$df_data[[input$variable.x]], 
                                          y = values$df_data[[input$variable.y]]
                                          )
                            ) + 
      theme(axis.text.x = element_text(angle = 90, hjust = 0.5), 
            plot.title = element_text(hjust = 0.5)
            ) +
      labs(list(title = paste(input$variable.x, "vs" ,input$variable.y, sep = " "), 
                x = input$variable.x, 
                y = input$variable.y, 
                color = "Group by:\n")
           )
    
    # define plot GEOMETRY
    if (input$plottype == "box") {
        observeEvent(input$variable.color, {
          if (input$variable.color == "NULL") {
            plot.dat$layer <- geom_boxplot()
            } else {
              plot.dat$layer <- geom_boxplot(mapping = aes(colour = values$df_data[[input$variable.color]]))
            }
          }
        )
      }
    
    if (input$plottype == "hist") {
       observeEvent(input$variable.color, {
         if (input$variable.color == "NULL") {
           plot.dat$layer <- geom_bar(stat = "identity")
         } else {
           plot.dat$layer <- geom_bar(mapping = aes(fill = values$df_data[[input$variable.color]]), 
                                      stat = "identity", 
                                      position = "dodge")
           }
         }
       )
    }
    
    if (input$plottype == "scat") {
      observeEvent(input$variable.color, {
        if (input$variable.color == "NULL") {
          plot.dat$layer <- geom_point()
          } else {
            plot.dat$layer <- geom_point(mapping = aes(colour = values$df_data[[input$variable.color]]), 
                                         stat = "identity")
            }
        }
      )
    }
    
    # download button 
    output$downloadbutton <- renderUI({
      #check.data()
      downloadButton(outputId = "download", 
                     label = " Download the plot")
      })
    })
   
  # download parameter generation
   observe({
     #check.data()
     output$plot <- renderPlot({plot.dat$main + plot.dat$layer})
     output$download <- downloadHandler(
       # specify the file name
       filename = function() {
         # paste("output", input$format)
         if (input$plottype == "box") {
           paste("boxplot_", input$variable.x,"_vs_", input$variable.y, ".png", sep = "")
         } else if (input$plottype == "hist") {
           paste("histogram_", input$variable.x,"_vs_", input$variable.y,  ".png", sep = "")
         } else if (input$plottype == "scat") {
           paste("scatterplot_",  input$variable.x,"_vs_", input$variable.y, ".png", sep = "")
         }
       } , 
       content = function(file) {
         # open the divice
         # create the plot
         # close the divice
         png(file, width = 1200, height = 800, units = "px")
         print(plot.dat$main + plot.dat$layer )
         dev.off()
         }
       )
     })

  
 #--------------------------- summary table -------------------------
  output$summary <- renderPrint({ 
    
    list(input$factors.slider, input$variable)
    #summary(values$df_data)
  })
   
})
